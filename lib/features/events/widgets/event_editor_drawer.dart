import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services/supabase_client.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/utils/event_permission_helper.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../../calendar/block_out_repository.dart';
import '../../calendar/calendar_controller.dart';
import '../../calendar/models/calendar_event.dart';
import '../../contacts/models/venue.dart';
import '../../contacts/venues_controller.dart';
import '../../gigs/gig_controller.dart';
import '../../gigs/gig_response_repository.dart';
import '../../members/members_controller.dart';
import '../../members/permissions/band_permissions_provider.dart';
import '../../rehearsals/rehearsal_controller.dart';
import '../../rehearsals/rehearsal_response_repository.dart';
import '../../setlists/new_setlist_screen.dart';
import '../models/event_form_data.dart';
import '../events_repository.dart';
import 'event_editor_actions.dart';
import 'event_editor_helpers.dart';
import 'event_form_fields.dart';
import 'event_type_selector.dart';
import 'gig_form_fields.dart';
import 'rehearsal_form_fields.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// EVENT EDITOR DRAWER
// A reusable drawer widget for creating/editing rehearsals and gigs.
// This is the single source of truth for event editing UI.
//
// USAGE:
//   showModalBottomSheet(
//     context: context,
//     builder: (_) => EventEditorDrawer(
//       mode: EventEditorMode.create,
//       initialEventType: EventType.rehearsal,
//       bandId: activeBandId,
//       onSaved: () => refresh(),
//     ),
//   );
// ============================================================================

/// Mode for the event editor
enum EventEditorMode { create, edit }

class EventEditorDrawer extends ConsumerStatefulWidget {
  /// Create mode or edit mode
  final EventEditorMode mode;

  /// Initial event type (rehearsal or gig)
  final EventType initialEventType;

  /// Initial date (prefilled from calendar day tap, etc.)
  final DateTime? initialDate;

  /// Existing event data for edit mode (nullable)
  final EventFormData? existingEvent;

  /// Existing event ID for edit mode (required for updates)
  final String? existingEventId;

  /// The band ID (required)
  final String bandId;

  /// Callback when event is saved successfully
  final VoidCallback? onSaved;

  /// Callback when editor is cancelled
  final VoidCallback? onCancelled;

  /// When true, all form fields are non-interactive and save/delete are hidden.
  /// Used for contributors who can view but not edit events.
  final bool viewOnly;

  /// Existing block out data for editing (block out events only)
  final BlockOutSpan? existingBlockOut;

  const EventEditorDrawer({
    super.key,
    this.mode = EventEditorMode.create,
    required this.initialEventType,
    this.initialDate,
    this.existingEvent,
    this.existingEventId,
    required this.bandId,
    this.onSaved,
    this.onCancelled,
    this.viewOnly = false,
    this.existingBlockOut,
  });

  @override
  ConsumerState<EventEditorDrawer> createState() => _EventEditorDrawerState();
}

class _EventEditorDrawerState extends ConsumerState<EventEditorDrawer>
    with SingleTickerProviderStateMixin {
  // Form state
  late EventType _eventType;
  late DateTime _selectedDate;
  int _selectedHour = 7;
  int _selectedMinutes = 0;
  bool _isPM = true;
  int _durationMinutes = 60; // Default 1h, stored in minutes
  // Load-in time state (gigs only, optional)
  int? _loadInHour;
  int? _loadInMinutes;
  bool? _loadInIsPM;
  final _locationController = TextEditingController();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  // Field hint controllers
  final _venueHintController = FieldHintController();
  final _cityHintController = FieldHintController();
  final _locationHintController = FieldHintController();
  final _notesHintController = FieldHintController();

  // Recurring state
  bool _isRecurring = false;
  Set<Weekday> _selectedDays = {};
  RecurrenceFrequency _frequency = RecurrenceFrequency.weekly;
  DateTime? _untilDate;

  // Block out state (block out events only)
  DateTime? _blockOutUntilDate;

  // Potential gig state (gigs only)
  // Selected members are persisted to gigs.required_member_ids column.
  // Empty set means all members are required (default).
  bool _isPotentialGig = false;
  Set<String> _selectedMemberIds = {};

  // RBAC: If true, contributor can only create potential gigs (toggle locked on)
  bool _forcePotentialOnly = false;

  // Multi-date state for potential gigs
  bool _isMultiDate = false;
  List<DateTime> _additionalDates = [];
  Map<DateTime, String> _existingGigDateIds = {}; // For edit mode

  // Member availability responses for potential gigs (edit mode only).
  // Maps userId -> 'yes', 'no', or null (not responded).
  Map<String, String?> _memberAvailability = {};
  bool _isLoadingMemberAvailability = false;

  // Per-date member availability for multi-date potential gigs (edit mode only).
  // Maps gigDateId (or 'primary' for main date) -> (userId -> response)
  Map<String, Map<String, String?>> _perDateAvailability = {};
  bool _isLoadingPerDateAvailability = false;

  // Current user's RSVP response for this potential gig (edit mode only)
  String? _currentUserResponse; // 'yes', 'no', or null
  bool _isLoadingUserResponse = false;

  // Setlist state
  String? _selectedSetlistId;
  String? _selectedSetlistName;

  // Gig pay controller (gigs only)
  final _gigPayController = CurrencyInputController();

  // Location autocomplete suggestions (loaded once from past rehearsals)
  List<String> _locationSuggestions = [];

  // Gig autocomplete suggestions (fetched as user types)
  List<String> _gigNameSuggestions = [];
  List<String> _gigCitySuggestions = [];
  Timer? _gigNameDebounceTimer;
  Timer? _gigCityDebounceTimer;

  // Linked venue state
  String? _selectedVenueId;

  // Focus nodes for autocomplete fields (must be persistent, not created inline)
  final _gigNameFocusNode = FocusNode();
  final _gigCityFocusNode = FocusNode();
  final _gigLocationFocusNode = FocusNode();

  // Animation for recurring section
  late AnimationController _recurringAnimController;
  late Animation<double> _recurringFadeAnimation;
  late Animation<Offset> _recurringSlideAnimation;

  // Loading / error state
  bool _isSaving = false;
  bool _isDeleting = false;
  String? _errorMessage;
  final Map<String, String> _fieldErrors = {};

  // Initial state tracking for edit mode (to detect changes)
  EventFormData? _initialFormData;

  // Simple dirty flag - set to true when user modifies any field in edit mode
  bool _isDirty = false;

  /// Mark form as dirty (user made a change)
  void _markDirty() {
    if (widget.mode == EventEditorMode.edit && !_isDirty) {
      setState(() => _isDirty = true);
    }
  }

  /// Trigger rebuild in create mode so _isFormValid is re-evaluated
  /// as the user types in required fields.
  void _onFormFieldChanged() {
    if (widget.mode == EventEditorMode.create) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();

    _eventType = widget.initialEventType;
    _selectedDate = widget.initialDate ?? DateTime.now();

    // Set default day based on selected date
    _selectedDays = {Weekday.values[_selectedDate.weekday % 7]};

    // Populate fields for edit mode
    if (widget.existingEvent != null) {
      final data = widget.existingEvent!;
      _eventType = data.type;
      _selectedDate = data.date;
      _selectedHour = data.hour;
      _selectedMinutes = data.minutes;
      _isPM = data.isPM;
      _durationMinutes = data.duration.minutes;
      // Populate load-in time if present
      if (data.loadInHour != null &&
          data.loadInMinutes != null &&
          data.loadInIsPM != null) {
        _loadInHour = data.loadInHour;
        _loadInMinutes = data.loadInMinutes;
        _loadInIsPM = data.loadInIsPM;
      }
      _locationController.text = data.location;
      if (data.name != null) _nameController.text = data.name!;
      if (data.notes != null) _notesController.text = data.notes!;
      _isRecurring = data.isRecurring;
      if (data.recurrence != null) {
        _selectedDays = data.recurrence!.daysOfWeek;
        _frequency = data.recurrence!.frequency;
        _untilDate = data.recurrence!.untilDate;
      }
      // Populate potential gig state for edit mode
      _isPotentialGig = data.isPotentialGig;
      _selectedMemberIds = Set.from(data.selectedMemberIds);
      // Populate multi-date state for edit mode
      _isMultiDate = data.additionalDates.isNotEmpty;
      _additionalDates = List.from(data.additionalDates);
      _existingGigDateIds = Map.from(data.existingGigDateIds);
      // Populate setlist state for edit mode
      _selectedSetlistId = data.setlistId;
      _selectedSetlistName = data.setlistName;

      // Populate gig pay for edit mode
      if (data.gigPayCents != null) {
        _gigPayController.cents = data.gigPayCents!;
      }

      // Populate linked venue for edit mode
      _selectedVenueId = data.venueId;

      // Store initial form data for change detection in edit mode
      _initialFormData = data;
    }

    // Populate fields for block out edit mode
    if (widget.existingBlockOut != null) {
      _eventType = EventType.blockOut;
      _selectedDate = widget.existingBlockOut!.startDate;
      if (widget.existingBlockOut!.isMultiDay) {
        _blockOutUntilDate = widget.existingBlockOut!.endDate;
      }
      _notesController.text = widget.existingBlockOut!.reason;
    }

    // Load members for potential gig section
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(membersProvider.notifier).loadMembers(widget.bandId);
      ref.read(venuesProvider.notifier).load(widget.bandId);
      _loadLocationSuggestions();

      // RBAC: If contributor with potential-only permission, force potential gig mode
      if (widget.mode == EventEditorMode.create &&
          _eventType == EventType.gig) {
        final permissionsAsync = ref.read(currentUserPermissionsProvider);
        permissionsAsync.whenData((perms) {
          if (perms.canCreatePotentialGigsOnly && mounted) {
            setState(() {
              _isPotentialGig = true;
              _forcePotentialOnly = true;
            });
            // Pre-select all members so validation passes
            _preSelectAllMembersForPotentialGig();
          }
        });
      }

      // Load current user's RSVP response and all member availability for potential gig in edit mode
      if (widget.mode == EventEditorMode.edit &&
          widget.existingEventId != null &&
          _isPotentialGig) {
        _loadCurrentUserResponse();
        _loadMemberAvailability();

        // Load per-date availability for multi-date potential gigs
        if (_isMultiDate && _additionalDates.isNotEmpty) {
          _loadPerDateAvailability();
        }

        // Pre-select all members for potential gig in edit mode
        // since selectedMemberIds isn't persisted to the database
        _preSelectAllMembersForPotentialGig();
      }
    });

    // Recurring section animation - 250ms with easeOut for snappy + smooth feel
    _recurringAnimController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _recurringFadeAnimation = CurvedAnimation(
      parent: _recurringAnimController,
      curve: Curves.easeOut,
    );

    _recurringSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _recurringAnimController,
        curve: Curves.easeOut,
      ),
    );

    if (_isRecurring) {
      _recurringAnimController.value = 1.0;
    }

    // Initialize field hint controllers
    final isEdit = widget.existingEvent != null;
    _venueHintController.initialize(
      hasInitialValue: isEdit && _nameController.text.isNotEmpty,
    );
    _cityHintController.initialize(
      hasInitialValue: isEdit && _locationController.text.isNotEmpty,
    );
    _locationHintController.initialize(
      hasInitialValue: isEdit && _locationController.text.isNotEmpty,
    );
    _notesHintController.initialize(
      hasInitialValue: isEdit && _notesController.text.isNotEmpty,
    );

    // Add text controller listeners to track changes
    _locationController.addListener(_markDirty);
    _nameController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    _gigPayController.addListener(_markDirty);

    // Re-evaluate form validity in create mode on required field changes
    _nameController.addListener(_onFormFieldChanged);
    _locationController.addListener(_onFormFieldChanged);
  }

  @override
  void dispose() {
    _gigNameDebounceTimer?.cancel();
    _gigCityDebounceTimer?.cancel();
    _locationController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _gigPayController.dispose();
    _venueHintController.dispose();
    _cityHintController.dispose();
    _locationHintController.dispose();
    _notesHintController.dispose();
    _recurringAnimController.dispose();
    _gigNameFocusNode.dispose();
    _gigCityFocusNode.dispose();
    _gigLocationFocusNode.dispose();
    super.dispose();
  }

  /// Load past rehearsal locations for autocomplete suggestions
  Future<void> _loadLocationSuggestions() async {
    try {
      // Query distinct non-null locations from past rehearsals for this band
      // Order by most recent to prioritize frequently used locations
      final response = await supabase
          .from('rehearsals')
          .select('location, date')
          .eq('band_id', widget.bandId)
          .not('location', 'is', null)
          .neq('location', '')
          .order('date', ascending: false)
          .limit(50);

      // Extract unique locations case-insensitively, preserving order (most recent first)
      final Set<String> seenLower = {};
      final List<String> suggestions = [];
      for (final row in response) {
        final location = row['location'] as String?;
        if (location != null && location.isNotEmpty) {
          final lower = location.toLowerCase();
          if (!seenLower.contains(lower)) {
            seenLower.add(lower);
            suggestions.add(location);
            if (suggestions.length >= 15) break; // Max 15 suggestions
          }
        }
      }

      if (mounted) {
        setState(() {
          _locationSuggestions = suggestions;
        });
        debugPrint(
          '[RehearsalLocation] loaded ${suggestions.length} suggestions for ${widget.bandId}',
        );
      }
    } catch (e) {
      debugPrint('[RehearsalLocation] Error loading suggestions: $e');
      // Fail silently - autocomplete is optional enhancement
    }
  }

  /// Load the current user's RSVP response for this potential gig
  Future<void> _loadCurrentUserResponse() async {
    final eventId = widget.existingEventId;
    final userId = supabase.auth.currentUser?.id;

    if (eventId == null || userId == null) return;

    setState(() => _isLoadingUserResponse = true);

    try {
      final String? response;

      if (_eventType == EventType.gig) {
        response = await ref
            .read(gigResponseRepositoryProvider)
            .fetchUserResponse(gigId: eventId, userId: userId);
      } else {
        response = await ref
            .read(rehearsalResponseRepositoryProvider)
            .fetchUserResponse(rehearsalId: eventId, userId: userId);
      }

      if (mounted) {
        setState(() {
          _currentUserResponse = response;
          _isLoadingUserResponse = false;
        });
      }
    } catch (e) {
      debugPrint('[EventEditorDrawer] Error loading user response: $e');
      if (mounted) {
        setState(() => _isLoadingUserResponse = false);
      }
    }
  }

  /// Load all member availability responses for this potential event (edit mode)
  Future<void> _loadMemberAvailability() async {
    final eventId = widget.existingEventId;
    if (eventId == null) return;

    setState(() => _isLoadingMemberAvailability = true);

    try {
      final Map<String, String?> responses;

      if (_eventType == EventType.gig) {
        responses = await ref
            .read(gigResponseRepositoryProvider)
            .fetchAllMemberResponses(gigId: eventId, bandId: widget.bandId);
      } else {
        responses = await ref
            .read(rehearsalResponseRepositoryProvider)
            .fetchAllMemberResponses(
                rehearsalId: eventId, bandId: widget.bandId);
      }

      if (mounted) {
        setState(() {
          _memberAvailability = responses;
          _isLoadingMemberAvailability = false;
        });
      }
    } catch (e) {
      debugPrint('[EventEditorDrawer] Error loading member availability: $e');
      if (mounted) {
        setState(() => _isLoadingMemberAvailability = false);
      }
    }
  }

  /// Pre-select all members for potential gig in edit mode IF no members were persisted.
  /// If requiredMemberIds was loaded from the database, we use that selection instead.
  void _preSelectAllMembersForPotentialGig() {
    debugPrint(
      '[EventEditorDrawer] _preSelectAllMembersForPotentialGig called',
    );
    debugPrint(
      '[EventEditorDrawer] Current selection: ${_selectedMemberIds.length} members',
    );

    // If we already have a selection from the database, don't override it
    if (_selectedMemberIds.isNotEmpty) {
      debugPrint(
        '[EventEditorDrawer] Using persisted selection of ${_selectedMemberIds.length} members',
      );
      return;
    }

    // Wait for members to load, then select all as default
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      // Check again in case selection was set while waiting
      if (_selectedMemberIds.isNotEmpty) {
        debugPrint(
          '[EventEditorDrawer] Selection was set while waiting, using that',
        );
        return;
      }

      final members = ref.read(membersProvider).members;
      debugPrint('[EventEditorDrawer] Members loaded: ${members.length}');

      if (members.isNotEmpty) {
        // Pre-select all members as default when no selection was persisted
        final allMemberIds = members.map((m) => m.userId).toSet();
        setState(() {
          _selectedMemberIds = allMemberIds;
          // Also update initialFormData so this doesn't count as a change
          // (since all members selected is the intended default for potential gigs)
          // IMPORTANT: Create a copy of the Set to avoid reference issues -
          // otherwise mutations to _selectedMemberIds also affect _initialFormData
          if (_initialFormData != null) {
            _initialFormData = _initialFormData!.copyWith(
              selectedMemberIds: Set<String>.from(_selectedMemberIds),
            );
          }
        });
        debugPrint(
          '[EventEditorDrawer] Pre-selected ${_selectedMemberIds.length} members for potential gig (default)',
        );
      } else {
        // Members not loaded yet, try again
        debugPrint('[EventEditorDrawer] Members not loaded yet, retrying...');
        _preSelectAllMembersForPotentialGig();
      }
    });
  }

  /// Submit the current user's RSVP response
  // ignore: unused_element
  Future<void> _submitUserResponse(String response) async {
    debugPrint(
      '[EventEditorDrawer] _submitUserResponse called with: $response',
    );

    final gigId = widget.existingEventId;
    final userId = supabase.auth.currentUser?.id;

    debugPrint('[EventEditorDrawer] gigId: $gigId, userId: $userId');

    if (gigId == null || userId == null) {
      debugPrint('[EventEditorDrawer] gigId or userId is null, returning');
      return;
    }

    // Don't submit if same response
    if (_currentUserResponse == response) {
      debugPrint('[EventEditorDrawer] Same response, returning');
      return;
    }

    debugPrint('[EventEditorDrawer] Starting submission...');

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      debugPrint('[EventEditorDrawer] Calling upsertResponse...');
      await ref.read(gigResponseRepositoryProvider).upsertResponse(
            gigId: gigId,
            bandId: widget.bandId,
            userId: userId,
            response: response,
          );
      debugPrint('[EventEditorDrawer] upsertResponse succeeded!');

      if (mounted) {
        setState(() {
          _currentUserResponse = response;
        });

        // Refresh gig data to update counts
        ref.read(gigProvider.notifier).refresh();

        // Invalidate response summaries provider so the dashboard updates immediately.
        // This is the key fix for availability count sync with Potential Gig cards.
        // The provider will re-fetch fresh data from the database.
        ref.invalidate(potentialGigResponseSummariesProvider);

        // Call onSaved to trigger any additional callbacks (e.g., calendar refresh)
        widget.onSaved?.call();

        showSuccessSnackBar(
          context,
          message: response == 'yes'
              ? 'You\'re available!'
              : 'Got it — you\'re not available.',
        );
      }
    } on GigResponseError catch (e) {
      debugPrint('[EventEditorDrawer] GigResponseError: ${e.message}');
      if (mounted) {
        showErrorSnackBar(context, message: e.userMessage);
      }
    } catch (e, stackTrace) {
      debugPrint('[EventEditorDrawer] Error submitting response: $e');
      debugPrint('[EventEditorDrawer] Stack trace: $stackTrace');
      if (mounted) {
        showErrorSnackBar(
          context,
          message: 'Something went wrong — try again in a moment.',
        );
      }
    }
  }

  /// Fetch gig name suggestions from the band's venues list (local filter)
  void _fetchGigNameSuggestions(String query) {
    // Clear suggestions if query is too short
    if (query.length < 2) {
      if (_gigNameSuggestions.isNotEmpty) {
        setState(() => _gigNameSuggestions = []);
      }
      // Clear venue link if user is editing the name
      if (_selectedVenueId != null) {
        _selectedVenueId = null;
      }
      return;
    }

    final venues = ref.read(venuesProvider).venues;
    final queryLower = query.toLowerCase();
    final suggestions = venues
        .where((v) => v.name.toLowerCase().contains(queryLower))
        .map((v) => v.name)
        .take(15)
        .toList();

    // Check if current text exactly matches a venue to auto-link
    final exactMatch = venues.cast<Venue?>().firstWhere(
          (v) => v!.name.toLowerCase() == queryLower,
          orElse: () => null,
        );
    if (exactMatch != null) {
      _selectedVenueId = exactMatch.id;
      // Auto-fill city from venue if city is set and location field is empty
      if (exactMatch.city != null &&
          exactMatch.city!.isNotEmpty &&
          _locationController.text.trim().isEmpty) {
        final cityState = [
          exactMatch.city,
          if (exactMatch.state != null && exactMatch.state!.isNotEmpty)
            exactMatch.state,
        ].join(', ');
        _locationController.text = cityState;
      }
    } else {
      _selectedVenueId = null;
    }

    if (mounted) {
      setState(() => _gigNameSuggestions = suggestions);
      debugPrint('[GigNameAutocomplete] "$query" -> ${suggestions.length}');
    }
  }

  /// Fetch gig city suggestions with debounce (from past gig cities for this band)
  void _fetchGigCitySuggestions(String query) {
    _gigCityDebounceTimer?.cancel();

    // Clear suggestions if query is too short
    if (query.length < 2) {
      if (_gigCitySuggestions.isNotEmpty) {
        setState(() => _gigCitySuggestions = []);
      }
      return;
    }

    _gigCityDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        // Query distinct cities from past gigs for this band
        // prefix-matched, case-insensitive
        final response = await supabase
            .from('gigs')
            .select('city, date')
            .eq('band_id', widget.bandId)
            .not('city', 'is', null)
            .neq('city', '')
            .ilike('city', '$query%')
            .order('date', ascending: false)
            .limit(30);

        // Dedupe case-insensitively and limit to 15
        final Set<String> seenLower = {};
        final List<String> suggestions = [];
        for (final row in response) {
          final city = row['city'] as String?;
          if (city != null && city.isNotEmpty) {
            final lower = city.toLowerCase();
            if (!seenLower.contains(lower)) {
              seenLower.add(lower);
              suggestions.add(city);
              if (suggestions.length >= 15) break;
            }
          }
        }

        if (mounted) {
          setState(() => _gigCitySuggestions = suggestions);
          debugPrint('[GigCityAutocomplete] "$query" -> ${suggestions.length}');
        }
      } catch (e) {
        debugPrint('[GigCityAutocomplete] Error: $e');
        // Fail silently
      }
    });
  }

  void _toggleRecurring(bool value) {
    HapticFeedback.lightImpact();
    setState(() {
      _isRecurring = value;
      // Auto-select the current day of week when enabling
      if (value && _selectedDays.isEmpty) {
        final currentDayIndex = _selectedDate.weekday % 7; // Convert to 0=Sun
        final currentDay = Weekday.values.firstWhere(
          (d) => d.dayIndex == currentDayIndex,
        );
        _selectedDays.add(currentDay);
      }
    });
    _markDirty();
    if (value) {
      _recurringAnimController.forward();
    } else {
      _recurringAnimController.reverse();
    }
  }

  void _togglePotentialGig(bool value) {
    setState(() {
      _isPotentialGig = value;
      // When enabling potential gig, select all members by default
      if (value && _selectedMemberIds.isEmpty) {
        final members = ref.read(membersProvider).members;
        _selectedMemberIds = members.map((m) => m.userId).toSet();
      }
      // When disabling potential gig, reset multi-date state
      if (!value) {
        _isMultiDate = false;
        _additionalDates = [];
      }
    });
    _markDirty();
  }

  void _addAdditionalDate() {
    setState(() {
      _isMultiDate = true;
      // Add a new date, default to one week after the last date
      final lastDate =
          _additionalDates.isNotEmpty ? _additionalDates.last : _selectedDate;
      _additionalDates.add(lastDate.add(const Duration(days: 7)));
    });
    _markDirty();
  }

  void _removeAdditionalDate(int index) {
    setState(() {
      final dateToRemove = _additionalDates[index];
      _additionalDates.removeAt(index);
      // Also remove from existingGigDateIds if present
      _existingGigDateIds.remove(dateToRemove);
      if (_additionalDates.isEmpty) _isMultiDate = false;
    });
    _markDirty();
  }

  void _updateAdditionalDate(int index, DateTime newDate) {
    setState(() {
      final oldDate = _additionalDates[index];
      _additionalDates[index] = newDate;
      // Update existingGigDateIds if the old date had an ID
      if (_existingGigDateIds.containsKey(oldDate)) {
        final id = _existingGigDateIds.remove(oldDate);
        if (id != null) {
          _existingGigDateIds[newDate] = id;
        }
      }
    });
    _markDirty();
  }

  EventFormData _buildFormData() {
    return EventFormData(
      type: _eventType,
      date: _selectedDate,
      hour: _selectedHour,
      minutes: _selectedMinutes,
      isPM: _isPM,
      duration: _durationMinutesToEnum(_durationMinutes),
      location: _locationController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      isRecurring: _isRecurring,
      recurrence: _isRecurring
          ? RecurrenceConfig(
              daysOfWeek: _selectedDays,
              frequency: _frequency,
              untilDate: _untilDate,
            )
          : null,
      loadInHour: _loadInHour,
      loadInMinutes: _loadInMinutes,
      loadInIsPM: _loadInIsPM,
      isPotentialGig: _isPotentialGig,
      selectedMemberIds: _selectedMemberIds,
      additionalDates: _isMultiDate ? _additionalDates : [],
      existingGigDateIds: _existingGigDateIds,
      setlistId: _selectedSetlistId,
      setlistName: _selectedSetlistName,
      gigPayCents: _eventType == EventType.gig && _gigPayController.isNotEmpty
          ? _gigPayController.cents
          : null,
      venueId: _selectedVenueId,
    );
  }

  /// Check if required fields are filled for gigs in create mode.
  /// For gigs: name and location are required.
  /// For rehearsals: no required text fields.
  bool get _isFormValid {
    if (_eventType == EventType.blockOut) {
      return true; // Block outs have no required text fields
    }
    if (_eventType == EventType.gig) {
      final hasName = _nameController.text.trim().isNotEmpty;
      final hasLocation = _locationController.text.trim().isNotEmpty;
      return hasName && hasLocation;
    }
    // Rehearsals have no required text fields
    return true;
  }

  /// Convert duration in minutes to the closest EventDuration enum value.
  /// If exact match not found, returns the closest higher value or max.
  EventDuration _durationMinutesToEnum(int minutes) {
    // Try to find an exact match first
    for (final d in EventDuration.values) {
      if (d.minutes == minutes) return d;
    }
    // If no exact match, find the closest higher value
    for (final d in EventDuration.values) {
      if (d.minutes >= minutes) return d;
    }
    // If minutes exceeds all options, return the max
    return EventDuration.values.last;
  }

  /// Whether this is edit mode
  bool get _isEditMode => widget.mode == EventEditorMode.edit;

  /// Check if the selected date conflicts with any band member's block-out dates.
  /// Returns a list of member names who are unavailable on this date.
  Future<List<String>> _checkBlockOutConflicts() async {
    try {
      // Fetch block-outs for the band
      final blockOuts = await ref
          .read(blockOutRepositoryProvider)
          .fetchBlockOutsForBand(widget.bandId);

      // Normalize selected date to midnight for comparison
      final normalizedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      // Find block-outs that match this date
      final conflictingBlockOuts = blockOuts.where((blockOut) {
        final blockOutDate = DateTime(
          blockOut.date.year,
          blockOut.date.month,
          blockOut.date.day,
        );
        return blockOutDate.isAtSameMomentAs(normalizedDate);
      }).toList();

      if (conflictingBlockOuts.isEmpty) {
        return [];
      }

      // Fetch member names for conflicting user IDs
      final userIds = conflictingBlockOuts.map((bo) => bo.userId).toSet();
      final membersState = ref.read(membersProvider);
      final unavailableMembers = <String>[];

      for (final userId in userIds) {
        final member =
            membersState.members.where((m) => m.userId == userId).firstOrNull;
        if (member != null) {
          unavailableMembers.add(member.name);
        }
      }

      return unavailableMembers;
    } catch (e) {
      // If check fails, don't block the save - just log and continue
      debugPrint('[EventEditor] Block-out conflict check failed: $e');
      return [];
    }
  }

  /// Show a non-blocking informational dialog about block-out conflicts
  Future<void> _showBlockOutConflictDialog(
    List<String> unavailableMembers,
  ) async {
    if (!mounted) return;

    final message = unavailableMembers.length == 1
        ? 'Band member ${unavailableMembers.first} is not available this day.'
        : 'Band members ${unavailableMembers.join(", ")} are not available this day.';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Availability Notice',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Text(
          message,
          style: AppTextStyles.callout
              .copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // BLOCK OUT SAVE / DELETE
  // ============================================================================

  /// Save a new block out
  Future<void> _saveBlockOut() async {
    if (widget.viewOnly) return;

    // RBAC: Block outs are for admins and members only
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final perms = permsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (err, stack) => null,
    );
    if (perms?.isContributor == true) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Block outs are for admins and members.',
        );
      }
      return;
    }

    // Validate end date
    if (_blockOutUntilDate != null &&
        _blockOutUntilDate!.isBefore(_selectedDate)) {
      setState(() {
        _errorMessage = 'End date cannot be before start date';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not logged in');
      }

      final repository = ref.read(blockOutRepositoryProvider);

      if (_isEditMode && widget.existingBlockOut != null) {
        // Update: delete span then create new
        await repository.deleteBlockOutSpan(
          userId: widget.existingBlockOut!.userId,
          bandId: widget.bandId,
          startDate: widget.existingBlockOut!.startDate,
          endDate: widget.existingBlockOut!.endDate,
        );
        await repository.createBlockOut(
          bandId: widget.bandId,
          userId: userId,
          startDate: _selectedDate,
          untilDate: _blockOutUntilDate,
          reason: _notesController.text.trim(),
        );
      } else {
        await repository.createBlockOut(
          bandId: widget.bandId,
          userId: userId,
          startDate: _selectedDate,
          untilDate: _blockOutUntilDate,
          reason: _notesController.text.trim(),
        );
      }

      // Refresh calendar
      ref
          .read(calendarProvider.notifier)
          .invalidateAndRefresh(bandId: widget.bandId);

      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call();
        showSuccessSnackBar(
          context,
          message: _isEditMode ? 'Block out updated' : 'Block out added',
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = mapBlockOutErrorToMessage(e, context: 'save');
      });
    }
  }

  /// Delete a block out span
  Future<void> _deleteBlockOut() async {
    if (widget.existingBlockOut == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Delete Block Out?', style: AppTextStyles.title3),
        content: Text(
          'This will remove the block out dates. This action cannot be undone.',
          style: AppTextStyles.callout
              .copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppTextStyles.callout.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(blockOutRepositoryProvider);

      await repository.deleteBlockOutSpan(
        userId: widget.existingBlockOut!.userId,
        bandId: widget.bandId,
        startDate: widget.existingBlockOut!.startDate,
        endDate: widget.existingBlockOut!.endDate,
      );

      // Refresh calendar
      ref
          .read(calendarProvider.notifier)
          .invalidateAndRefresh(bandId: widget.bandId);

      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call();
        showSuccessSnackBar(context, message: 'Block out deleted');
      }
    } catch (e) {
      setState(() {
        _isDeleting = false;
        _errorMessage = mapBlockOutErrorToMessage(e, context: 'delete');
      });
    }
  }

  Future<void> _handleSave() async {
    // Route block out saves to dedicated handler
    if (_eventType == EventType.blockOut) {
      await _saveBlockOut();
      return;
    }

    // RBAC self-defense: block save if viewOnly or insufficient permissions
    if (widget.viewOnly) return;
    final savePermsAsync = ref.read(currentUserPermissionsProvider);
    final perms = savePermsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (err2, stack2) => null,
    );
    if (perms != null) {
      if (widget.mode == EventEditorMode.create && !perms.canCreateGigs) {
        if (mounted) {
          showAppSnackBar(context,
              message: 'You don\'t have permission to create events.');
        }
        return;
      }
      if (widget.mode == EventEditorMode.edit && !perms.canEditGigs) {
        // Allow contributors to save edits to potential gigs
        if (!(_isPotentialGig && perms.canEditPotentialGigs)) {
          if (mounted) {
            showAppSnackBar(context,
                message: 'You don\'t have permission to edit events.');
          }
          return;
        }
      }
    }

    // Clear previous errors
    setState(() {
      _errorMessage = null;
    });

    // Validate
    var formData = _buildFormData();
    final errors = formData.validate();

    if (errors.isNotEmpty) {
      setState(() {
        _errorMessage = errors.first;
      });
      return;
    }

    // Check for block-out conflicts (non-blocking, informational only)
    final unavailableMembers = await _checkBlockOutConflicts();
    if (unavailableMembers.isNotEmpty) {
      await _showBlockOutConflictDialog(unavailableMembers);
      // Continue with save after showing dialog
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final repository = ref.read(eventsRepositoryProvider);

      // Auto-create venue if user typed a name that doesn't match an existing venue
      if (_eventType == EventType.gig &&
          _selectedVenueId == null &&
          _nameController.text.trim().isNotEmpty) {
        final newVenue = await ref.read(venuesProvider.notifier).create(
          bandId: widget.bandId,
          data: {'name': _nameController.text.trim()},
        );
        if (newVenue != null) {
          _selectedVenueId = newVenue.id;
          formData = formData.copyWith(venueId: newVenue.id);
        }
      }

      if (widget.mode == EventEditorMode.edit &&
          widget.existingEventId != null) {
        // Update existing event
        if (_eventType == EventType.rehearsal) {
          await repository.updateRehearsal(
            rehearsalId: widget.existingEventId!,
            bandId: widget.bandId,
            formData: formData,
            // Pass original recurrence state to detect transition to recurring
            wasRecurring: _initialFormData?.isRecurring,
          );
        } else {
          await repository.updateGig(
            gigId: widget.existingEventId!,
            bandId: widget.bandId,
            formData: formData,
          );

          // Save user availability response if set (potential gigs only)
          if (_isPotentialGig && _currentUserResponse != null) {
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              await ref.read(gigResponseRepositoryProvider).upsertResponse(
                    gigId: widget.existingEventId!,
                    bandId: widget.bandId,
                    userId: userId,
                    response: _currentUserResponse!,
                  );

              // Invalidate response summaries provider so dashboard updates immediately.
              // This is critical for syncing availability counts on Potential Gig cards.
              ref.invalidate(potentialGigResponseSummariesProvider);
            }
          }

          // Save per-date availability responses for multi-date potential gigs
          if (_isPotentialGig &&
              _isMultiDate &&
              _perDateAvailability.isNotEmpty) {
            await _savePerDateResponses();
          }
        }
      } else {
        // Create new event
        if (_eventType == EventType.rehearsal) {
          await repository.createRehearsal(
            bandId: widget.bandId,
            formData: formData,
          );
        } else {
          await repository.createGig(bandId: widget.bandId, formData: formData);
        }
      }

      // Invalidate cache
      repository.invalidateCache(widget.bandId);

      // Refresh providers directly to ensure immediate UI update
      // This is more reliable than relying on onSaved callback after pop
      ref.read(gigProvider.notifier).refresh();
      ref.read(rehearsalProvider.notifier).refresh();
      ref
          .read(calendarProvider.notifier)
          .invalidateAndRefresh(bandId: widget.bandId);

      // Success feedback
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call();

        showSuccessSnackBar(
          context,
          message: widget.mode == EventEditorMode.edit
              ? '${_eventType.displayName} updated'
              : '${_eventType.displayName} created',
        );
      }
    } catch (e, st) {
      debugPrint('[EventEditor] ERROR saving event:');
      debugPrint('  Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  Stack: $st');
      setState(() {
        _isSaving = false;
        _errorMessage = _mapErrorToMessage(e);
      });
    }
  }

  /// Maps errors to user-friendly messages for event save/update operations.
  /// Uses centralized helper for consistent messaging.
  String _mapErrorToMessage(Object error) {
    final errorStr = error.toString().toLowerCase();

    // Recurrence not supported yet - special case
    if (errorStr.contains('recurrence') || errorStr.contains('recurring')) {
      return 'Recurring events coming soon!';
    }

    // In debug mode, surface the actual Supabase error for diagnosis
    if (kDebugMode) {
      debugPrint('[EventEditor] Raw error for diagnosis: $error');
    }

    // Use centralized helper for all other errors
    // Context is 'add' for create mode, 'update' for edit mode
    final context = widget.mode == EventEditorMode.edit ? 'update' : 'add';
    return mapEventErrorToMessage(error, context: context);
  }

  /// Check if this rehearsal is part of a recurring series
  bool get _isPartOfRecurringSeries {
    if (_eventType != EventType.rehearsal) return false;
    // A rehearsal is part of a series if it's recurring OR has a parent
    return _initialFormData?.isRecurring == true ||
        _initialFormData?.parentRehearsalId != null;
  }

  /// Show delete confirmation dialog and handle deletion
  Future<void> _showDeleteConfirmation() async {
    // Route block out deletes to dedicated handler
    if (_eventType == EventType.blockOut) {
      await _deleteBlockOut();
      return;
    }

    // For recurring rehearsals, show special dialog with options
    if (_isPartOfRecurringSeries) {
      await _showRecurringDeleteDialog();
      return;
    }

    // Standard delete confirmation for non-recurring events
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Event?',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Text(
          'This action cannot be undone.',
          style: AppTextStyles.callout
              .copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _handleDelete(deleteEntireSeries: false);
    }
  }

  /// Show delete dialog for recurring rehearsals with options
  Future<void> _showRecurringDeleteDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Recurring Rehearsal?',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Text(
          'This rehearsal is part of a recurring series.',
          style: AppTextStyles.callout
              .copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text(
              'Cancel',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('this'),
            child: Text(
              'Delete This Only',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('all'),
            child: Text(
              'Delete All',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == 'this') {
      await _handleDelete(deleteEntireSeries: false);
    } else if (result == 'all') {
      await _handleDelete(deleteEntireSeries: true);
    }
  }

  /// Delete the event
  Future<void> _handleDelete({required bool deleteEntireSeries}) async {
    if (widget.existingEventId == null) return;

    // RBAC self-defense: block delete if viewOnly or insufficient permissions
    if (widget.viewOnly) return;
    final deletePermsAsync = ref.read(currentUserPermissionsProvider);
    final deletePerms = deletePermsAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (err3, stack3) => null,
    );
    if (deletePerms != null && !deletePerms.canDeleteGigs) {
      // Allow contributors to delete potential gigs they can edit
      if (!(_isPotentialGig && deletePerms.canEditPotentialGigs)) {
        if (mounted) {
          showAppSnackBar(context,
              message: 'You don\'t have permission to delete events.');
        }
        return;
      }
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(eventsRepositoryProvider);

      if (_eventType == EventType.rehearsal) {
        if (deleteEntireSeries && _isPartOfRecurringSeries) {
          // Delete the entire recurring series
          debugPrint(
            '[DeleteEvent] Attempting to delete series:\n'
            '  existingEventId: ${widget.existingEventId}\n'
            '  initialFormData.isRecurring: ${_initialFormData?.isRecurring}\n'
            '  initialFormData.parentRehearsalId: ${_initialFormData?.parentRehearsalId}',
          );
          await repository.deleteRehearsalSeries(
            rehearsalId: widget.existingEventId!,
            bandId: widget.bandId,
            parentRehearsalId: _initialFormData?.parentRehearsalId,
          );
          debugPrint(
            '[DeleteEvent] deleted recurring rehearsal series for ${widget.existingEventId}',
          );
        } else {
          // Delete only this single rehearsal
          await repository.deleteRehearsal(
            rehearsalId: widget.existingEventId!,
            bandId: widget.bandId,
          );
          debugPrint(
            '[DeleteEvent] deleted rehearsal ${widget.existingEventId} for band ${widget.bandId}',
          );
        }
      } else {
        await repository.deleteGig(
          gigId: widget.existingEventId!,
          bandId: widget.bandId,
        );
        debugPrint(
          '[DeleteEvent] deleted gig ${widget.existingEventId} for band ${widget.bandId}',
        );
      }

      // Invalidate cache
      repository.invalidateCache(widget.bandId);

      debugPrint('[EventEditorDrawer] Refreshing providers after delete...');

      // Refresh providers directly to ensure immediate UI update
      // This is more reliable than relying on onSaved callback after pop
      // Await both to ensure data is refreshed before closing drawer
      await Future.wait([
        ref.read(gigProvider.notifier).refresh(),
        ref.read(rehearsalProvider.notifier).refresh(),
      ]);
      await ref
          .read(calendarProvider.notifier)
          .invalidateAndRefresh(bandId: widget.bandId);

      debugPrint('[EventEditorDrawer] Refresh complete, popping...');

      // Success feedback
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call(); // Refresh caller's data (dashboard + calendar)
        debugPrint('[EventEditorDrawer] onSaved called');

        final message = deleteEntireSeries && _isPartOfRecurringSeries
            ? 'All recurring rehearsals deleted'
            : '${_eventType.displayName} deleted';
        showSuccessSnackBar(context, message: message);
      }
    } catch (e) {
      setState(() {
        _isDeleting = false;
        _errorMessage = _mapDeleteErrorToMessage(e);
      });
    }
  }

  /// Maps errors to user-friendly messages for event delete operations.
  /// Uses centralized helper for consistent messaging.
  String _mapDeleteErrorToMessage(Object error) {
    // Use centralized helper for consistent messaging
    return mapEventErrorToMessage(error, context: 'delete');
  }

  String get _primaryButtonLabel {
    final typeName = _eventType.displayName;
    return widget.mode == EventEditorMode.edit ? 'Update' : 'Add $typeName';
  }

  // --- Helpers for extracted widget construction ---

  List<EventType> _computeAvailableTypes() {
    final permsAsync = ref.read(currentUserPermissionsProvider);
    final isContributor =
        permsAsync.whenOrNull(data: (p) => p.isContributor) ?? false;
    return isContributor
        ? EventType.values
            .where((t) => t != EventType.rehearsal && t != EventType.blockOut)
            .toList()
        : EventType.values;
  }

  void _handleTypeChanged(EventType type) {
    setState(() {
      _eventType = type;
    });
    if (type == EventType.gig && widget.mode == EventEditorMode.create) {
      final permsAsync = ref.read(currentUserPermissionsProvider);
      permsAsync.whenData((perms) {
        if (perms.canCreatePotentialGigsOnly && mounted) {
          setState(() {
            _isPotentialGig = true;
            _forcePotentialOnly = true;
          });
          _preSelectAllMembersForPotentialGig();
        }
      });
    }
    HapticFeedback.selectionClick();
  }

  GigFormFields _createGigFormFields() {
    return GigFormFields(
      isSaving: _isSaving,
      isEditMode: _isEditMode,
      existingEventId: widget.existingEventId,
      nameController: _nameController,
      venueHintController: _venueHintController,
      gigNameFocusNode: _gigNameFocusNode,
      gigNameSuggestions: _gigNameSuggestions,
      onGigNameChanged: _fetchGigNameSuggestions,
      fieldErrors: _fieldErrors,
      locationController: _locationController,
      cityHintController: _cityHintController,
      gigCityFocusNode: _gigCityFocusNode,
      gigCitySuggestions: _gigCitySuggestions,
      onGigCityChanged: _fetchGigCitySuggestions,
      isPotentialGig: _isPotentialGig,
      forcePotentialOnly: _forcePotentialOnly,
      onPotentialGigToggled: _togglePotentialGig,
      memberAvailability: _memberAvailability,
      isLoadingMemberAvailability: _isLoadingMemberAvailability,
      perDateAvailability: _perDateAvailability,
      isLoadingPerDateAvailability: _isLoadingPerDateAvailability,
      currentUserResponse: _currentUserResponse,
      isLoadingUserResponse: _isLoadingUserResponse,
      onUserResponseChanged: (response) {
        setState(() => _currentUserResponse = response);
        _markDirty();
        HapticFeedback.selectionClick();
      },
      isMultiDate: _isMultiDate,
      additionalDates: _additionalDates,
      selectedDate: _selectedDate,
      existingGigDateIds: _existingGigDateIds,
      onPerDateResponseChanged: _updatePerDateResponse,
      loadInHour: _loadInHour,
      loadInMinutes: _loadInMinutes,
      loadInIsPM: _loadInIsPM,
      onLoadInTimeSet: () {
        setState(() {
          _loadInHour = 6;
          _loadInMinutes = 0;
          _loadInIsPM = true;
        });
        _markDirty();
      },
      onLoadInTimeCleared: () {
        setState(() {
          _loadInHour = null;
          _loadInMinutes = null;
          _loadInIsPM = null;
        });
        _markDirty();
      },
      onLoadInHourChanged: (v) {
        setState(() => _loadInHour = v);
        _markDirty();
      },
      onLoadInMinutesChanged: (v) {
        setState(() => _loadInMinutes = v);
        _markDirty();
      },
      onLoadInAmPmChanged: (isPM) {
        setState(() => _loadInIsPM = isPM);
        _markDirty();
        HapticFeedback.selectionClick();
      },
      gigPayController: _gigPayController,
      onMarkDirty: _markDirty,
      currentUserId: supabase.auth.currentUser?.id,
    );
  }

  EventFormFields _createEventFormFields(BuildContext context) {
    return EventFormFields(
      eventType: _eventType,
      isSaving: _isSaving,
      errorMessage: null,
      selectedDate: _selectedDate,
      onDateTap: _showDatePicker,
      isPotentialGig: _isPotentialGig,
      isMultiDate: _isMultiDate,
      additionalDates: _additionalDates,
      onAdditionalDateTap: (i) => _showAdditionalDatePicker(i),
      onAdditionalDateRemoved: _removeAdditionalDate,
      onAdditionalDateAdded: _addAdditionalDate,
      selectedHour: _selectedHour,
      selectedMinutes: _selectedMinutes,
      isPM: _isPM,
      onHourChanged: (v) {
        setState(() => _selectedHour = v);
        _markDirty();
      },
      onMinutesChanged: (v) {
        setState(() => _selectedMinutes = v);
        _markDirty();
      },
      onAmPmChanged: (isPM) {
        setState(() => _isPM = isPM);
        _markDirty();
        HapticFeedback.selectionClick();
      },
      durationMinutes: _durationMinutes,
      onDurationDecremented: () {
        setState(() {
          _durationMinutes = (_durationMinutes - 15).clamp(15, 9999);
        });
        _markDirty();
      },
      onDurationIncremented: () {
        setState(() {
          _durationMinutes += 15;
        });
        _markDirty();
      },
      selectedSetlistId: _selectedSetlistId,
      onSetlistSelected: (id, name) {
        setState(() {
          _selectedSetlistId = id;
          _selectedSetlistName = name;
        });
        _markDirty();
      },
      onNavigateToCreateSetlist: () {
        Navigator.of(context).push(
          fadeSlideRoute(page: const NewSetlistScreen()),
        );
      },
      notesController: _notesController,
      notesHintController: _notesHintController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final eventFormFields = _createEventFormFields(context);
    final gigFormFields =
        _eventType == EventType.gig ? _createGigFormFields() : null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.viewOnly
                        ? '${_eventType.displayName} Details'
                        : widget.mode == EventEditorMode.edit
                            ? 'Edit ${_eventType.displayName}'
                            : 'Add Event',
                    style: AppTextStyles.pageTitle.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop(false);
                    widget.onCancelled?.call();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.colors.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.close,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Scrollable content
          Flexible(
            child: AbsorbPointer(
              absorbing: widget.viewOnly,
              child: Opacity(
                opacity: widget.viewOnly ? 0.7 : 1.0,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: Spacing.pagePadding,
                    right: Spacing.pagePadding,
                    bottom: bottomPadding + safeBottom + 100,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_errorMessage != null) ...[
                        _buildErrorBanner(),
                        const SizedBox(height: Spacing.space16),
                      ],

                      // Event Type Toggle
                      EventTypeSelector(
                        selectedType: _eventType,
                        availableTypes: _computeAvailableTypes(),
                        isEditMode: _isEditMode,
                        isSaving: _isSaving,
                        onTypeChanged: _handleTypeChanged,
                      ),

                      const SizedBox(height: Spacing.space20),

                      // Gig name + potential gig (gig only)
                      if (_eventType == EventType.gig) ...[
                        gigFormFields!,
                        const SizedBox(height: Spacing.space12),
                      ],

                      // Block out form
                      if (_eventType == EventType.blockOut) ...[
                        _buildBlockOutForm(),
                        if (_isEditMode && !widget.viewOnly) ...[
                          const SizedBox(height: Spacing.space24),
                          EventDeleteButton(
                            isSaving: _isSaving,
                            isDeleting: _isDeleting,
                            onDelete: _showDeleteConfirmation,
                          ),
                        ],
                      ] else ...[
                        // Shared: date, time, duration
                        eventFormFields,

                        // Location/City (type-specific)
                        if (_eventType == EventType.rehearsal) ...[
                          RehearsalFormFields(
                            isSaving: _isSaving,
                            locationController: _locationController,
                            locationHintController: _locationHintController,
                            locationSuggestions: _locationSuggestions,
                            isPotential: _isPotentialGig,
                            onPotentialToggled: _togglePotentialGig,
                            isRecurring: _isRecurring,
                            onRecurringToggled: _toggleRecurring,
                            recurringSlideAnimation: _recurringSlideAnimation,
                            recurringFadeAnimation: _recurringFadeAnimation,
                            selectedDays: _selectedDays,
                            onDayToggled: (day) {
                              setState(() {
                                if (_selectedDays.contains(day)) {
                                  _selectedDays.remove(day);
                                } else {
                                  _selectedDays.add(day);
                                }
                              });
                              _markDirty();
                            },
                            frequency: _frequency,
                            onFrequencyChanged: (freq) {
                              setState(() => _frequency = freq);
                              _markDirty();
                            },
                            untilDate: _untilDate,
                            onUntilDateTap: _showUntilDatePicker,
                            onUntilDateCleared: () {
                              setState(() => _untilDate = null);
                              _markDirty();
                            },
                            selectedDate: _selectedDate,
                            onMarkDirty: _markDirty,
                            memberAvailability: _memberAvailability,
                            isLoadingMemberAvailability:
                                _isLoadingMemberAvailability,
                            isLoadingUserResponse: _isLoadingUserResponse,
                            currentUserResponse: _currentUserResponse,
                            onUserResponseChanged: (response) {
                              setState(() => _currentUserResponse = response);
                              _markDirty();
                              HapticFeedback.selectionClick();
                            },
                            isEditMode: widget.mode == EventEditorMode.edit,
                            existingEventId: widget.existingEventId,
                          ),
                        ] else ...[
                          gigFormFields!.buildCityAutocomplete(context),
                          const SizedBox(height: Spacing.space16),
                          gigFormFields.buildLoadInTimeSelector(context),
                        ],

                        const SizedBox(height: Spacing.space16),

                        // Setlist selector
                        eventFormFields.buildSetlistSelector(context, ref),

                        // Gig Pay (gigs only)
                        if (_eventType == EventType.gig) ...[
                          const SizedBox(height: Spacing.space16),
                          gigFormFields!.buildGigPayField(),
                        ],

                        const SizedBox(height: Spacing.space16),

                        // Notes
                        eventFormFields.buildNotesSection(),

                        const SizedBox(height: Spacing.space20),

                        // Delete button (edit mode only)
                        if (_isEditMode && !widget.viewOnly) ...[
                          const SizedBox(height: Spacing.space24),
                          EventDeleteButton(
                            isSaving: _isSaving,
                            isDeleting: _isDeleting,
                            onDelete: _showDeleteConfirmation,
                          ),
                        ],
                      ], // end else (non-blockOut form)
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom action buttons — padded above keyboard when visible
          Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: widget.viewOnly
                ? EventEditorViewOnlyClose(
                    onClose: () {
                      Navigator.of(context).pop(false);
                      widget.onCancelled?.call();
                    },
                  )
                : EventEditorBottomActions(
                    canSave: !_isSaving &&
                        !_isDeleting &&
                        _isFormValid &&
                        (widget.mode == EventEditorMode.create || _isDirty),
                    isSaving: _isSaving,
                    isDeleting: _isDeleting,
                    primaryButtonLabel: _primaryButtonLabel,
                    onSave: _handleSave,
                    onCancel: () {
                      Navigator.pop(context);
                      widget.onCancelled?.call();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // WIDGET BUILDERS
  // ============================================================================

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            AppIcons.error,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.callout.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // BLOCK OUT FORM
  // ============================================================================

  Widget _buildBlockOutForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Start Date
        _buildBlockOutDateField(
          label: 'Start Date',
          date: _selectedDate,
          onTap: _isSaving ? null : _selectBlockOutStartDate,
        ),
        const SizedBox(height: Spacing.space16),

        // End Date (optional)
        _buildBlockOutDateField(
          label: 'End Date (optional)',
          date: _blockOutUntilDate,
          onTap: _isSaving ? null : _selectBlockOutUntilDate,
          placeholder: 'Same as start date',
          showClearButton: _blockOutUntilDate != null,
          onClear: () {
            setState(() => _blockOutUntilDate = null);
            _markDirty();
          },
        ),
        const SizedBox(height: Spacing.space16),

        // Reason (optional)
        EventTextField(
          label: 'Reason (optional)',
          controller: _notesController,
          hint: 'Vacation, personal, etc.',
          maxLines: 2,
          isSaving: _isSaving,
        ),
      ],
    );
  }

  Widget _buildBlockOutDateField({
    required String label,
    DateTime? date,
    VoidCallback? onTap,
    String placeholder = '',
    bool showClearButton = false,
    VoidCallback? onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.calendar,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    date != null ? _formatBlockOutDate(date) : placeholder,
                    style: AppTextStyles.callout.copyWith(
                      color: date != null
                          ? context.colors.textPrimary
                          : context.colors.textMuted,
                    ),
                  ),
                ),
                if (showClearButton)
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      AppIcons.close,
                      size: 18,
                      color: context.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectBlockOutStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) => _blockOutDatePickerTheme(child),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        if (_blockOutUntilDate != null &&
            _blockOutUntilDate!.isBefore(_selectedDate)) {
          _blockOutUntilDate = null;
        }
      });
      _markDirty();
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _selectBlockOutUntilDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _blockOutUntilDate ?? _selectedDate,
      firstDate: _selectedDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) => _blockOutDatePickerTheme(child),
    );
    if (picked != null) {
      setState(() => _blockOutUntilDate = picked);
      _markDirty();
      HapticFeedback.selectionClick();
    }
  }

  Widget _blockOutDatePickerTheme(Widget? child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
          primary: AppColors.primary,
          surface: context.colors.surface,
          onSurface: context.colors.textPrimary,
        ),
        dialogTheme: DialogThemeData(backgroundColor: context.colors.surface),
      ),
      child: child!,
    );
  }

  String _formatBlockOutDate(DateTime date) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _showAdditionalDatePicker(int index) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _additionalDates[index],
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
              primary: AppColors.primary,
              surface: context.colors.surface,
              onSurface: context.colors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      _updateAdditionalDate(index, picked);
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _showDatePicker() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
              primary: AppColors.primary,
              surface: context.colors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Update selected days for recurring
        _selectedDays = {Weekday.values[picked.weekday % 7]};
      });
      _markDirty();
    }
  }

  /// Update the user's response for a specific date (local state only, saved on form save)
  void _updatePerDateResponse(
    DateTime date,
    bool isPrimaryDate,
    String response,
  ) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final dateKey = isPrimaryDate ? 'primary' : _existingGigDateIds[date];
    if (dateKey == null) return;

    setState(() {
      _perDateAvailability[dateKey] = {
        ...(_perDateAvailability[dateKey] ?? {}),
        userId: response,
      };

      // Also update single-date response if this is the primary date
      // for backward compatibility
      if (isPrimaryDate) {
        _currentUserResponse = response;
      }
    });

    _markDirty();
    HapticFeedback.selectionClick();
  }

  /// Load per-date availability for multi-date potential gigs
  Future<void> _loadPerDateAvailability() async {
    final gigId = widget.existingEventId;
    if (gigId == null || !_isMultiDate) return;

    setState(() => _isLoadingPerDateAvailability = true);

    try {
      final gigDateIds = _existingGigDateIds.values.toList();
      final responses =
          await ref.read(gigResponseRepositoryProvider).fetchAllDateResponses(
                gigId: gigId,
                bandId: widget.bandId,
                gigDateIds: gigDateIds,
              );

      if (mounted) {
        setState(() {
          _perDateAvailability = responses;
          _isLoadingPerDateAvailability = false;
        });
      }
    } catch (e) {
      debugPrint('[EventEditorDrawer] Error loading per-date availability: $e');
      if (mounted) {
        setState(() => _isLoadingPerDateAvailability = false);
      }
    }
  }

  /// Save per-date availability responses for multi-date potential gigs
  Future<void> _savePerDateResponses() async {
    final gigId = widget.existingEventId;
    final userId = supabase.auth.currentUser?.id;
    if (gigId == null || userId == null) return;

    final repo = ref.read(gigResponseRepositoryProvider);

    for (final entry in _perDateAvailability.entries) {
      final dateKey = entry.key;
      final responses = entry.value;
      final userResponse = responses[userId];

      if (userResponse != null) {
        // Determine gigDateId (null for primary date)
        final gigDateId = dateKey == 'primary' ? null : dateKey;

        await repo.upsertResponseForDate(
          gigId: gigId,
          gigDateId: gigDateId,
          userId: userId,
          response: userResponse,
        );
      }
    }
  }

  Future<void> _showUntilDatePicker() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _untilDate ?? _selectedDate.add(const Duration(days: 30)),
      firstDate: _selectedDate,
      lastDate: _selectedDate.add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
              primary: AppColors.primary,
              surface: context.colors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _untilDate = picked;
      });
      _markDirty();
    }
  }
}
