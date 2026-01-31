import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services/supabase_client.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/utils/event_permission_helper.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../shared/utils/title_case_formatter.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../../calendar/block_out_repository.dart';
import '../../calendar/calendar_controller.dart';
import '../../gigs/gig_controller.dart';
import '../../gigs/gig_response_repository.dart';
import '../../members/members_controller.dart';
import '../../members/member_vm.dart';
import '../../rehearsals/rehearsal_controller.dart';
import '../../setlists/models/setlist.dart';
import '../../setlists/new_setlist_screen.dart';
import '../../setlists/setlists_screen.dart' show setlistsProvider;
import '../models/event_form_data.dart';
import '../events_repository.dart';
import 'button_group_grid.dart';

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

  // Potential gig state (gigs only)
  // Selected members are persisted to gigs.required_member_ids column.
  // Empty set means all members are required (default).
  bool _isPotentialGig = false;
  Set<String> _selectedMemberIds = {};

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
  Map<String, String?> _initialPerDateUserResponses =
      {}; // Track initial per-date responses for current user
  bool _isLoadingPerDateAvailability = false;

  // Current user's RSVP response for this potential gig (edit mode only)
  String? _currentUserResponse; // 'yes', 'no', or null
  String? _initialUserResponse; // Track initial value for change detection
  bool _isLoadingUserResponse = false;
  bool _isSubmittingUserResponse = false;

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

      // Store initial form data for change detection in edit mode
      _initialFormData = data;
    }

    // Load members for potential gig section
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(membersProvider.notifier).loadMembers(widget.bandId);
      _loadLocationSuggestions();

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
    final gigId = widget.existingEventId;
    final userId = supabase.auth.currentUser?.id;

    if (gigId == null || userId == null) return;

    setState(() => _isLoadingUserResponse = true);

    try {
      final response = await ref
          .read(gigResponseRepositoryProvider)
          .fetchUserResponse(gigId: gigId, userId: userId);

      if (mounted) {
        setState(() {
          _currentUserResponse = response;
          _initialUserResponse = response; // Track for change detection
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

  /// Load all member availability responses for this potential gig (edit mode)
  Future<void> _loadMemberAvailability() async {
    final gigId = widget.existingEventId;
    if (gigId == null) return;

    setState(() => _isLoadingMemberAvailability = true);

    try {
      final responses = await ref
          .read(gigResponseRepositoryProvider)
          .fetchAllMemberResponses(gigId: gigId, bandId: widget.bandId);

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

    setState(() => _isSubmittingUserResponse = true);
    debugPrint('[EventEditorDrawer] Starting submission...');

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      debugPrint('[EventEditorDrawer] Calling upsertResponse...');
      await ref
          .read(gigResponseRepositoryProvider)
          .upsertResponse(
            gigId: gigId,
            bandId: widget.bandId,
            userId: userId,
            response: response,
          );
      debugPrint('[EventEditorDrawer] upsertResponse succeeded!');

      if (mounted) {
        setState(() {
          _currentUserResponse = response;
          _isSubmittingUserResponse = false;
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
              ? 'You\'re available! 🎸'
              : 'Got it — you\'re not available.',
        );
      }
    } on GigResponseError catch (e) {
      debugPrint('[EventEditorDrawer] GigResponseError: ${e.message}');
      if (mounted) {
        setState(() => _isSubmittingUserResponse = false);
        showErrorSnackBar(context, message: e.userMessage);
      }
    } catch (e, stackTrace) {
      debugPrint('[EventEditorDrawer] Error submitting response: $e');
      debugPrint('[EventEditorDrawer] Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isSubmittingUserResponse = false);
        showErrorSnackBar(
          context,
          message: 'Something went wrong — try again in a moment.',
        );
      }
    }
  }

  /// Fetch gig name suggestions with debounce (from past gig names for this band)
  void _fetchGigNameSuggestions(String query) {
    _gigNameDebounceTimer?.cancel();

    // Clear suggestions if query is too short
    if (query.length < 2) {
      if (_gigNameSuggestions.isNotEmpty) {
        setState(() => _gigNameSuggestions = []);
      }
      return;
    }

    _gigNameDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        // Query distinct gig names from past gigs for this band
        // prefix-matched, case-insensitive
        final response = await supabase
            .from('gigs')
            .select('name, date')
            .eq('band_id', widget.bandId)
            .not('name', 'is', null)
            .neq('name', '')
            .ilike('name', '$query%')
            .order('date', ascending: false)
            .limit(30);

        // Dedupe case-insensitively and limit to 15
        final Set<String> seenLower = {};
        final List<String> suggestions = [];
        for (final row in response) {
          final name = row['name'] as String?;
          if (name != null && name.isNotEmpty) {
            final lower = name.toLowerCase();
            if (!seenLower.contains(lower)) {
              seenLower.add(lower);
              suggestions.add(name);
              if (suggestions.length >= 15) break;
            }
          }
        }

        if (mounted) {
          setState(() => _gigNameSuggestions = suggestions);
          debugPrint('[GigNameAutocomplete] "$query" -> ${suggestions.length}');
        }
      } catch (e) {
        debugPrint('[GigNameAutocomplete] Error: $e');
        // Fail silently
      }
    });
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
  }

  void _toggleMultiDate(bool value) {
    setState(() {
      _isMultiDate = value;
      // When toggling off, remove all additional dates
      if (!value) {
        _additionalDates = [];
      }
    });
  }

  void _addAdditionalDate() {
    setState(() {
      // Add a new date, default to one week after the last date
      final lastDate = _additionalDates.isNotEmpty
          ? _additionalDates.last
          : _selectedDate;
      _additionalDates.add(lastDate.add(const Duration(days: 7)));
    });
  }

  void _removeAdditionalDate(int index) {
    setState(() {
      final dateToRemove = _additionalDates[index];
      _additionalDates.removeAt(index);
      // Also remove from existingGigDateIds if present
      _existingGigDateIds.remove(dateToRemove);
    });
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
      isPotentialGig: _eventType == EventType.gig && _isPotentialGig,
      selectedMemberIds: _selectedMemberIds,
      additionalDates: _isMultiDate ? _additionalDates : [],
      existingGigDateIds: _existingGigDateIds,
      setlistId: _selectedSetlistId,
      setlistName: _selectedSetlistName,
      gigPayCents: _eventType == EventType.gig && _gigPayController.isNotEmpty
          ? _gigPayController.cents
          : null,
    );
  }

  /// Check if form has changes from initial state (edit mode only)
  bool get _hasChanges {
    if (widget.mode != EventEditorMode.edit || _initialFormData == null) {
      return true; // Always allow save in create mode
    }
    final current = _buildFormData();
    final initial = _initialFormData!;

    // Compare all fields including gig-specific ones
    // For selectedMemberIds, compare as Sets with stable ordering
    final memberIdsChanged = !_setsEqual(
      current.selectedMemberIds,
      initial.selectedMemberIds,
    );

    // Check if additional dates changed (for multi-date potential gigs)
    final additionalDatesChanged = !_dateListsEqual(
      current.additionalDates,
      initial.additionalDates,
    );

    // Use normalized string comparison for text fields
    return current.type != initial.type ||
        current.date != initial.date ||
        current.hour != initial.hour ||
        current.minutes != initial.minutes ||
        current.isPM != initial.isPM ||
        current.duration != initial.duration ||
        current.loadInHour != initial.loadInHour ||
        current.loadInMinutes != initial.loadInMinutes ||
        current.loadInIsPM != initial.loadInIsPM ||
        !_stringsEqual(current.location, initial.location) ||
        !_stringsEqual(current.notes, initial.notes) ||
        !_stringsEqual(current.name, initial.name) ||
        current.isRecurring != initial.isRecurring ||
        current.isPotentialGig != initial.isPotentialGig ||
        memberIdsChanged ||
        additionalDatesChanged ||
        current.setlistId != initial.setlistId ||
        current.gigPayCents != initial.gigPayCents ||
        _currentUserResponse != _initialUserResponse ||
        _perDateUserResponsesChanged();
  }

  /// Check if per-date availability responses have changed for multi-date potential gigs
  bool _perDateUserResponsesChanged() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    if (!_isMultiDate || !_isPotentialGig) return false;

    // Build current user's per-date responses
    final currentResponses = <String, String?>{};
    for (final entry in _perDateAvailability.entries) {
      currentResponses[entry.key] = entry.value[userId];
    }

    // Compare with initial
    if (currentResponses.length != _initialPerDateUserResponses.length) {
      return true;
    }
    for (final entry in currentResponses.entries) {
      if (_initialPerDateUserResponses[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  /// Check if required fields are filled for gigs in create mode.
  /// For gigs: name and location are required.
  /// For rehearsals: no required text fields.
  bool get _isFormValid {
    if (_eventType == EventType.gig) {
      final hasName = _nameController.text.trim().isNotEmpty;
      final hasLocation = _locationController.text.trim().isNotEmpty;
      return hasName && hasLocation;
    }
    // Rehearsals have no required text fields
    return true;
  }

  /// Helper to compare two Sets for equality
  bool _setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b) && b.containsAll(a);
  }

  /// Helper to compare two lists of DateTime for equality
  bool _dateListsEqual(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // Compare by date only (year, month, day)
      if (a[i].year != b[i].year ||
          a[i].month != b[i].month ||
          a[i].day != b[i].day) {
        return false;
      }
    }
    return true;
  }

  /// Helper to compare strings with normalization.
  /// Treats null and empty string as equivalent.
  /// Trims whitespace and collapses repeated spaces.
  bool _stringsEqual(String? a, String? b) {
    final normalizedA = _normalizeString(a);
    final normalizedB = _normalizeString(b);
    return normalizedA == normalizedB;
  }

  /// Normalize a string: trim, collapse whitespace, treat null as empty.
  String _normalizeString(String? s) {
    if (s == null) return '';
    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
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

  /// Format duration in minutes for display.
  /// Examples: 15m, 45m, 1h, 1h 15m, 2h 30m
  String _formatDurationMinutes(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
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
        final member = membersState.members
            .where((m) => m.userId == userId)
            .firstOrNull;
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
        backgroundColor: AppColors.cardBgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Availability Notice',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          message,
          style: AppTextStyles.callout.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    // Clear previous errors
    setState(() {
      _errorMessage = null;
    });

    // Validate
    final formData = _buildFormData();
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

          // Save user availability response if it changed (potential gigs only)
          if (_isPotentialGig &&
              _currentUserResponse != null &&
              _currentUserResponse != _initialUserResponse) {
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              await ref
                  .read(gigResponseRepositoryProvider)
                  .upsertResponse(
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
    } catch (e) {
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
    // For recurring rehearsals, show special dialog with options
    if (_isPartOfRecurringSeries) {
      await _showRecurringDeleteDialog();
      return;
    }

    // Standard delete confirmation for non-recurring events
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Event?',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'This action cannot be undone.',
          style: AppTextStyles.callout.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.textSecondary,
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
        backgroundColor: AppColors.cardBgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Recurring Rehearsal?',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'This rehearsal is part of a recurring series.',
          style: AppTextStyles.callout.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text(
              'Cancel',
              style: AppTextStyles.calloutEmphasized.copyWith(
                color: AppColors.textSecondary,
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

      // Refresh providers directly to ensure immediate UI update
      // This is more reliable than relying on onSaved callback after pop
      // Await both to ensure data is refreshed before closing drawer
      await Future.wait([
        ref.read(gigProvider.notifier).refresh(),
        ref.read(rehearsalProvider.notifier).refresh(),
      ]);
      ref
          .read(calendarProvider.notifier)
          .invalidateAndRefresh(bandId: widget.bandId);

      // Success feedback
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSaved?.call(); // Refresh caller's data (dashboard + calendar)

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

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderMuted,
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
                    widget.mode == EventEditorMode.edit
                        ? 'Edit ${_eventType.displayName}'
                        : 'Add Event',
                    style: AppTextStyles.title3,
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
                    decoration: const BoxDecoration(
                      color: AppColors.scaffoldBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Scrollable content
          Flexible(
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

                  // 1. Event Type Toggle
                  _buildEventTypeToggle(),

                  const SizedBox(height: Spacing.space20),

                  // Gig name field (only for gigs) - with autocomplete
                  if (_eventType == EventType.gig) ...[
                    _buildGigNameAutocomplete(),
                    const SizedBox(height: Spacing.space16),

                    // Potential Gig Section - wrapped with optional rose border
                    _buildPotentialGigContainer(),

                    const SizedBox(height: Spacing.space12),
                  ],

                  // 2. Date Picker
                  _buildDatePicker(),

                  const SizedBox(height: Spacing.space16),

                  // 3. Start Time Selectors
                  _buildTimeSelector(),

                  const SizedBox(height: Spacing.space16),

                  // 4. Duration Toggles (4x2 grid)
                  _buildDurationSelector(),

                  const SizedBox(height: Spacing.space16),

                  // 5. Location/City Input (context-aware label)
                  // Rehearsals get autocomplete from past locations
                  // Gigs get autocomplete from past cities
                  _eventType == EventType.rehearsal
                      ? _buildLocationAutocomplete()
                      : _buildGigCityAutocomplete(),

                  // 5.5 Load-in Time (gigs only, optional)
                  if (_eventType == EventType.gig) ...[
                    const SizedBox(height: Spacing.space16),
                    _buildLoadInTimeSelector(),
                  ],

                  const SizedBox(height: Spacing.space16),

                  // 6. Setlist Selector (optional for both gigs and rehearsals)
                  _buildSetlistSelector(),

                  // 7. Gig Pay (gigs only, optional)
                  if (_eventType == EventType.gig) ...[
                    const SizedBox(height: Spacing.space16),
                    _buildGigPayField(),
                  ],

                  const SizedBox(height: Spacing.space16),

                  // Notes (optional)
                  _buildTextField(
                    label: 'Notes (optional)',
                    controller: _notesController,
                    hint: 'Any additional details...',
                    maxLines: 3,
                  ),
                  FieldHint(
                    text: "Optional — visible only to band members.",
                    controller: _notesHintController,
                  ),

                  const SizedBox(height: Spacing.space20),

                  // 6. Recurring Toggle (rehearsals only - gigs don't recur)
                  if (_eventType == EventType.rehearsal) ...[
                    _buildRecurringToggle(),

                    // 7. Recurring Section (animated with slide + fade)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _isRecurring
                          ? SlideTransition(
                              position: _recurringSlideAnimation,
                              child: FadeTransition(
                                opacity: _recurringFadeAnimation,
                                child: _buildRecurringSection(),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],

                  // Delete Event button (edit mode only)
                  if (_isEditMode) ...[
                    const SizedBox(height: Spacing.space24),
                    _buildDeleteButton(),
                  ],
                ],
              ),
            ),
          ),

          // 8. Bottom Buttons (sticky) - Equal width
          _buildBottomButtons(safeBottom, bottomPadding),
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
            Icons.error_outline_rounded,
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

  /// Delete button (destructive text style) - only shown in edit mode
  Widget _buildDeleteButton() {
    return Center(
      child: TextButton(
        onPressed: (_isSaving || _isDeleting) ? null : _showDeleteConfirmation,
        child: _isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.error,
                ),
              )
            : Text(
                'Delete Event',
                style: AppTextStyles.calloutEmphasized.copyWith(
                  color: AppColors.error,
                ),
              ),
      ),
    );
  }

  Widget _buildEventTypeToggle() {
    // In edit mode, the toggle is disabled to prevent type changes
    final isDisabled = _isEditMode || _isSaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: EventType.values.map((type) {
              final isSelected = _eventType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: isDisabled
                      ? null
                      : () {
                          setState(() {
                            _eventType = type;
                          });
                          HapticFeedback.selectionClick();
                        },
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDisabled
                                ? AppColors.accent.withValues(alpha: 0.5)
                                : AppColors.accent)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        Spacing.buttonRadius - 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      type.displayName,
                      style: AppTextStyles.calloutEmphasized.copyWith(
                        color: isSelected
                            ? (isDisabled
                                  ? AppColors.textPrimary.withValues(alpha: 0.7)
                                  : AppColors.textPrimary)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Helper text in edit mode
        if (_isEditMode) ...[
          const SizedBox(height: 6),
          Text(
            'Event type cannot be changed after creation.',
            style: AppTextStyles.footnote.copyWith(color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row with optional "Multiple" toggle for potential gigs
        Row(
          children: [
            Text(
              'Date',
              style: AppTextStyles.footnote.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            // Show "Multiple" toggle only for potential gigs
            if (_eventType == EventType.gig && _isPotentialGig)
              _buildMultipleDatesToggle(),
          ],
        ),
        const SizedBox(height: 6),
        // Primary date picker
        _buildSingleDatePicker(
          date: _selectedDate,
          onTap: _isSaving ? null : _showDatePicker,
          showRemoveButton: false,
        ),
        // Additional date pickers (when multi-date is enabled)
        if (_isMultiDate) ...[
          for (int i = 0; i < _additionalDates.length; i++) ...[
            const SizedBox(height: 8),
            _buildSingleDatePicker(
              date: _additionalDates[i],
              onTap: _isSaving ? null : () => _showAdditionalDatePicker(i),
              showRemoveButton: true,
              showAddButton: i == _additionalDates.length - 1,
              onRemove: () => _removeAdditionalDate(i),
              onAdd: _addAdditionalDate,
            ),
          ],
          // Show add button if no additional dates yet
          if (_additionalDates.isEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isSaving ? null : _addAdditionalDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(
                    color: AppColors.borderMuted,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Add another date',
                      style: AppTextStyles.callout.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Builds the "Multiple" toggle button
  Widget _buildMultipleDatesToggle() {
    return GestureDetector(
      onTap: _isSaving ? null : () => _toggleMultiDate(!_isMultiDate),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isMultiDate ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isMultiDate ? AppColors.accent : AppColors.borderMuted,
          ),
        ),
        child: Text(
          'Multiple',
          style: AppTextStyles.footnote.copyWith(
            color: _isMultiDate ? Colors.white : AppColors.textSecondary,
            fontWeight: _isMultiDate ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Builds a single date picker row
  Widget _buildSingleDatePicker({
    required DateTime date,
    required VoidCallback? onTap,
    required bool showRemoveButton,
    bool showAddButton = false,
    VoidCallback? onRemove,
    VoidCallback? onAdd,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: AppColors.borderMuted),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatDateDisplay(date),
                    style: AppTextStyles.callout.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Show +/- controls for additional dates (not the primary date)
        if (showRemoveButton || showAddButton) ...[
          const SizedBox(width: 8),
          // Remove button
          if (showRemoveButton)
            GestureDetector(
              onTap: _isSaving ? null : onRemove,
              child: Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: const Icon(
                  Icons.remove_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (showRemoveButton && showAddButton) const SizedBox(width: 4),
          // Add button (only on the last date picker)
          if (showAddButton)
            GestureDetector(
              onTap: _isSaving ? null : onAdd,
              child: Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _showAdditionalDatePicker(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _additionalDates[index],
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.cardBg,
              onSurface: AppColors.textPrimary,
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

  String _formatDateDisplay(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
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
    final dayName = days[date.weekday % 7];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}, ${date.year}';
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.cardBg,
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
    }
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start Time',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Hour dropdown
            Expanded(
              child: _buildDropdown(
                value: _selectedHour,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) => setState(() => _selectedHour = v!),
                labelBuilder: (v) => v.toString(),
              ),
            ),
            const SizedBox(width: 8),
            // Minutes dropdown
            Expanded(
              child: _buildDropdown(
                value: _selectedMinutes,
                items: [0, 15, 30, 45],
                onChanged: (v) => setState(() => _selectedMinutes = v!),
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(width: 8),
            // AM/PM toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAmPmButton('AM', !_isPM),
                  _buildAmPmButton('PM', _isPM),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Load-in time selector (optional, gigs only)
  /// Uses the same UI pattern as Start Time
  Widget _buildLoadInTimeSelector() {
    // If no load-in time is set, show a "Set Load-in Time" button
    if (_loadInHour == null || _loadInMinutes == null || _loadInIsPM == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Load-in Time',
            style: AppTextStyles.footnote.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _isSaving
                ? null
                : () {
                    setState(() {
                      _loadInHour = 6;
                      _loadInMinutes = 0;
                      _loadInIsPM = true;
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: AppColors.borderMuted),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Set Load-in Time (Optional)',
                    style: AppTextStyles.callout.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // If load-in time is set, show the picker with a clear button
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Load-in Time',
              style: AppTextStyles.footnote.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            GestureDetector(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _loadInHour = null;
                        _loadInMinutes = null;
                        _loadInIsPM = null;
                      });
                    },
              child: Text(
                'Clear',
                style: AppTextStyles.footnote.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Hour dropdown
            Expanded(
              child: _buildDropdown(
                value: _loadInHour!,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) => setState(() => _loadInHour = v!),
                labelBuilder: (v) => v.toString(),
              ),
            ),
            const SizedBox(width: 8),
            // Minutes dropdown
            Expanded(
              child: _buildDropdown(
                value: _loadInMinutes!,
                items: [0, 15, 30, 45],
                onChanged: (v) => setState(() => _loadInMinutes = v!),
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(width: 8),
            // AM/PM toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLoadInAmPmButton('AM', !_loadInIsPM!),
                  _buildLoadInAmPmButton('PM', _loadInIsPM!),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadInAmPmButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: _isSaving
          ? null
          : () {
              setState(() {
                _loadInIsPM = label == 'PM';
              });
              HapticFeedback.selectionClick();
            },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius - 2),
        ),
        child: Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    required String Function(T) labelBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.cardBgElevated,
          style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item)),
            );
          }).toList(),
          onChanged: _isSaving ? null : onChanged,
        ),
      ),
    );
  }

  Widget _buildAmPmButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: _isSaving
          ? null
          : () {
              setState(() {
                _isPM = label == 'PM';
              });
              HapticFeedback.selectionClick();
            },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius - 2),
        ),
        child: Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Duration selector with step-based +15/-15 minute controls
  Widget _buildDurationSelector() {
    const minDuration = 15;
    const rose700 = Color(0xFFBE123C);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duration',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // -15 button
            GestureDetector(
              onTap: _isSaving || _durationMinutes <= minDuration
                  ? null
                  : () {
                      setState(() {
                        _durationMinutes = (_durationMinutes - 15).clamp(
                          minDuration,
                          9999,
                        );
                      });
                    },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _durationMinutes <= minDuration
                        ? rose700.withOpacity(0.4)
                        : rose700,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '-15',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _durationMinutes <= minDuration
                          ? rose700.withOpacity(0.4)
                          : rose700,
                    ),
                  ),
                ),
              ),
            ),

            // Duration value
            SizedBox(
              width: 120,
              child: Center(
                child: Text(
                  _formatDurationMinutes(_durationMinutes),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // +15 button
            GestureDetector(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _durationMinutes += 15;
                      });
                    },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: rose700, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+15',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: rose700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? error,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_isSaving,
          maxLines: maxLines,
          textInputAction: TextInputAction.done,
          style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          // Trigger rebuild on text change so _hasChanges is re-evaluated
          // and the Update button enables/disables appropriately.
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.callout.copyWith(
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.scaffoldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.borderMuted,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.borderMuted,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.accent,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error,
            style: AppTextStyles.footnote.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  /// Build location field with autocomplete for rehearsals
  Widget _buildLocationAutocomplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _locationController.text),
          optionsBuilder: (TextEditingValue textEditingValue) {
            // Only show suggestions when input length >= 1
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            // Filter suggestions by case-insensitive contains, limit to 8
            final query = textEditingValue.text.toLowerCase();
            return _locationSuggestions
                .where((location) => location.toLowerCase().contains(query))
                .take(8);
          },
          onSelected: (String selection) {
            _locationController.text = selection;
            debugPrint('[RehearsalLocation] selected suggestion: $selection');
            setState(() {});
          },
          fieldViewBuilder:
              (
                BuildContext context,
                TextEditingController fieldController,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                // Sync the field controller with our location controller
                fieldController.addListener(() {
                  _locationController.text = fieldController.text;
                });
                return TextField(
                  controller: fieldController,
                  focusNode: focusNode,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [TitleCaseTextFormatter()],
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g., Studio, Venue Address',
                    hintStyle: AppTextStyles.callout.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(
                        color: AppColors.borderMuted,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(
                        color: AppColors.borderMuted,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                );
              },
          optionsViewBuilder:
              (
                BuildContext context,
                AutocompleteOnSelected<String> onSelected,
                Iterable<String> options,
              ) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgElevated,
                        borderRadius: BorderRadius.circular(
                          Spacing.buttonRadius,
                        ),
                        border: Border.all(color: AppColors.borderMuted),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(
                              option,
                              style: AppTextStyles.callout.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
        ),
        FieldHint(
          text: "We'll remember locations you've used before.",
          controller: _locationHintController,
        ),
      ],
    );
  }

  /// Build gig name field with autocomplete and title case
  Widget _buildGigNameAutocomplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gig Venue / Festival / Name',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        RawAutocomplete<String>(
          textEditingController: _nameController,
          focusNode: _gigNameFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            // Trigger async fetch (debounced)
            _fetchGigNameSuggestions(textEditingValue.text);
            // Return current suggestions
            if (textEditingValue.text.length < 2) {
              return const Iterable<String>.empty();
            }
            return _gigNameSuggestions;
          },
          onSelected: (String selection) {
            _nameController.text = selection;
            _nameController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
            setState(() => _gigNameSuggestions = []);
          },
          fieldViewBuilder:
              (
                BuildContext context,
                TextEditingController controller,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [TitleCaseTextFormatter()],
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g., The Blue Note, SummerFest 2026',
                    hintStyle: AppTextStyles.callout.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: BorderSide(
                        color: _fieldErrors['name'] != null
                            ? AppColors.error
                            : AppColors.borderMuted,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: BorderSide(
                        color: _fieldErrors['name'] != null
                            ? AppColors.error
                            : AppColors.borderMuted,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: BorderSide(
                        color: _fieldErrors['name'] != null
                            ? AppColors.error
                            : AppColors.accent,
                      ),
                    ),
                  ),
                );
              },
          optionsViewBuilder:
              (
                BuildContext context,
                AutocompleteOnSelected<String> onSelected,
                Iterable<String> options,
              ) {
                if (options.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width:
                          MediaQuery.of(context).size.width -
                          (Spacing.pagePadding * 2),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgElevated,
                        borderRadius: BorderRadius.circular(
                          Spacing.buttonRadius,
                        ),
                        border: Border.all(color: AppColors.borderMuted),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(
                              option,
                              style: AppTextStyles.callout.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
        ),
        if (_fieldErrors['name'] != null) ...[
          const SizedBox(height: 4),
          Text(
            _fieldErrors['name']!,
            style: AppTextStyles.footnote.copyWith(color: AppColors.error),
          ),
        ],
        FieldHint(
          text: "Start typing to reuse past venues.",
          controller: _venueHintController,
        ),
      ],
    );
  }

  /// Build city field with autocomplete and title case (for gigs)
  Widget _buildGigCityAutocomplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'City',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        RawAutocomplete<String>(
          // Key forces rebuild when suggestions update from async fetch
          key: ValueKey(
            'gigCity_${_gigCitySuggestions.length}_${_gigCitySuggestions.hashCode}',
          ),
          textEditingController: _locationController,
          focusNode: _gigCityFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            // Trigger async fetch (debounced)
            _fetchGigCitySuggestions(textEditingValue.text);
            // Return current suggestions
            if (textEditingValue.text.length < 2) {
              return const Iterable<String>.empty();
            }
            return _gigCitySuggestions;
          },
          onSelected: (String selection) {
            _locationController.text = selection;
            _locationController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
            setState(() => _gigCitySuggestions = []);
          },
          fieldViewBuilder:
              (
                BuildContext context,
                TextEditingController controller,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [TitleCaseTextFormatter()],
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g., Chicago, IL',
                    hintStyle: AppTextStyles.callout.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(
                        color: AppColors.borderMuted,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(
                        color: AppColors.borderMuted,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                );
              },
          optionsViewBuilder:
              (
                BuildContext context,
                AutocompleteOnSelected<String> onSelected,
                Iterable<String> options,
              ) {
                if (options.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width:
                          MediaQuery.of(context).size.width -
                          (Spacing.pagePadding * 2),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgElevated,
                        borderRadius: BorderRadius.circular(
                          Spacing.buttonRadius,
                        ),
                        border: Border.all(color: AppColors.borderMuted),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(
                              option,
                              style: AppTextStyles.callout.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
        ),
        FieldHint(
          text: "Auto-fills based on past gigs.",
          controller: _cityHintController,
        ),
      ],
    );
  }

  // ============================================================================
  // POTENTIAL GIG SECTION
  // ============================================================================

  /// Builds the entire Potential Gig container with optional rose border
  Widget _buildPotentialGigContainer() {
    final membersState = ref.watch(membersProvider);
    final members = membersState.members;

    // Check if this is a multi-date potential gig in edit mode
    final isMultiDateEditMode =
        widget.mode == EventEditorMode.edit &&
        widget.existingEventId != null &&
        _isMultiDate &&
        _additionalDates.isNotEmpty;

    // Container with conditional rose border when toggle is ON
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: _isPotentialGig
            ? Border.all(color: AppColors.accent, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Title + Toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Gig',
                      style: AppTextStyles.callout.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requires member confirmation before gig is official.',
                      style: AppTextStyles.footnote.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isPotentialGig,
                onChanged: _isSaving ? null : _togglePotentialGig,
                activeTrackColor: AppColors.accent,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.textPrimary;
                  }
                  return null;
                }),
              ),
            ],
          ),

          // Member grid (only visible when toggle is ON)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _isPotentialGig
                ? isMultiDateEditMode
                      // Multi-date layout: per-date sections
                      ? _buildMultiDateAvailabilitySection(
                          members,
                          membersState.isLoading,
                        )
                      // Single-date layout: existing behavior
                      : Column(
                          children: [
                            _buildMemberSelectionGrid(
                              members,
                              membersState.isLoading,
                            ),
                            // Your Availability section (edit mode only)
                            if (widget.mode == EventEditorMode.edit &&
                                widget.existingEventId != null)
                              _buildUserAvailabilitySection(),
                          ],
                        )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Builds the multi-date availability section with per-date member grids
  Widget _buildMultiDateAvailabilitySection(
    List<MemberVM> members,
    bool isLoading,
  ) {
    // Get all dates sorted
    final allDates = [_selectedDate, ..._additionalDates];
    allDates.sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.space12),
        // Per-date sections
        for (int i = 0; i < allDates.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.space16),
          _buildPerDateSection(
            date: allDates[i],
            dateIndex: i,
            members: members,
            isLoading: isLoading,
            isPrimaryDate: allDates[i] == _selectedDate,
          ),
        ],
      ],
    );
  }

  /// Builds a single date section with member availability grid
  Widget _buildPerDateSection({
    required DateTime date,
    required int dateIndex,
    required List<MemberVM> members,
    required bool isLoading,
    required bool isPrimaryDate,
  }) {
    // Determine the dateKey for this date
    final dateKey = isPrimaryDate ? 'primary' : _existingGigDateIds[date];
    final availability = dateKey != null
        ? _perDateAvailability[dateKey] ?? {}
        : <String, String?>{};

    // Get current user's response for this date
    final userId = supabase.auth.currentUser?.id;
    final userResponse = userId != null ? availability[userId] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space8),
          child: Text(
            _formatDateDisplay(date),
            style: AppTextStyles.calloutEmphasized.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),

        // Member availability grid (non-interactive, shows state)
        if (isLoading || _isLoadingPerDateAvailability)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
            child: Text(
              'No members to notify',
              style: AppTextStyles.footnote.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          ButtonGroupGrid<MemberVM>(
            items: members,
            labelBuilder: (member) => _getMemberLabel(member, members),
            labelWidgetBuilder: (member) =>
                _buildMemberLabelWidget(member, members),
            isSelected: (member) => false,
            availabilityMode: true,
            availabilityState: (member) {
              final response = availability[member.userId];
              if (response == 'yes') return AvailabilityState.available;
              if (response == 'no') return AvailabilityState.notAvailable;
              return AvailabilityState.notResponded;
            },
            onTap: null,
            columns: 4,
            buttonHeight: 48,
          ),

        // Your Availability for this date
        const SizedBox(height: Spacing.space8),
        Text(
          'Your Availability',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Row(
          children: [
            // NO button
            Expanded(
              child: _AvailabilityButton(
                label: 'NO',
                icon: Icons.close,
                isSelected: userResponse == 'no',
                isPositive: false,
                isLoading: false,
                onPressed: () =>
                    _updatePerDateResponse(date, isPrimaryDate, 'no'),
              ),
            ),
            const SizedBox(width: Spacing.space12),
            // YES button
            Expanded(
              child: _AvailabilityButton(
                label: 'YES',
                icon: Icons.check,
                isSelected: userResponse == 'yes',
                isPositive: true,
                isLoading: false,
                onPressed: () =>
                    _updatePerDateResponse(date, isPrimaryDate, 'yes'),
              ),
            ),
          ],
        ),
      ],
    );
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

    HapticFeedback.selectionClick();
  }

  /// Load per-date availability for multi-date potential gigs
  Future<void> _loadPerDateAvailability() async {
    final gigId = widget.existingEventId;
    if (gigId == null || !_isMultiDate) return;

    setState(() => _isLoadingPerDateAvailability = true);

    try {
      final gigDateIds = _existingGigDateIds.values.toList();
      final responses = await ref
          .read(gigResponseRepositoryProvider)
          .fetchAllDateResponses(
            gigId: gigId,
            bandId: widget.bandId,
            gigDateIds: gigDateIds,
          );

      if (mounted) {
        // Extract current user's initial responses for change detection
        final userId = supabase.auth.currentUser?.id;
        final initialUserResponses = <String, String?>{};
        if (userId != null) {
          for (final entry in responses.entries) {
            initialUserResponses[entry.key] = entry.value[userId];
          }
        }

        setState(() {
          _perDateAvailability = responses;
          _initialPerDateUserResponses = initialUserResponses;
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

  /// Builds the "Your Availability" section with YES/NO buttons
  Widget _buildUserAvailabilitySection() {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: Spacing.space12),
            color: AppColors.borderMuted,
          ),

          // Label
          Text(
            'Your Availability',
            style: AppTextStyles.footnote.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: Spacing.space8),

          // Loading state
          if (_isLoadingUserResponse)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.space8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            // NO / YES buttons
            Row(
              children: [
                // NO button
                Expanded(
                  child: _AvailabilityButton(
                    label: 'NO',
                    icon: Icons.close,
                    isSelected: _currentUserResponse == 'no',
                    isPositive: false,
                    isLoading: false,
                    onPressed: () {
                      setState(() => _currentUserResponse = 'no');
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),

                const SizedBox(width: Spacing.space12),

                // YES button
                Expanded(
                  child: _AvailabilityButton(
                    label: 'YES',
                    icon: Icons.check,
                    isSelected: _currentUserResponse == 'yes',
                    isPositive: true,
                    isLoading: false,
                    onPressed: () {
                      setState(() => _currentUserResponse = 'yes');
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Builds the member availability grid for potential gig.
  /// In potential gig mode, members are not selectable - they show availability state.
  Widget _buildMemberSelectionGrid(List<MemberVM> members, bool isLoading) {
    // Show loading indicator while loading members or availability
    if (isLoading || _isLoadingMemberAvailability) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
        child: Text(
          'No members to notify',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    // In potential gig mode, show availability state (non-interactive)
    // Members are not selectable - they just show their response status
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space12),
      child: ButtonGroupGrid<MemberVM>(
        items: members,
        labelBuilder: (member) => _getMemberLabel(member, members),
        labelWidgetBuilder: (member) =>
            _buildMemberLabelWidget(member, members),
        isSelected: (member) => false, // Not used in availability mode
        availabilityMode:
            true, // Always use availability mode for potential gigs
        availabilityState: (member) {
          final response = _memberAvailability[member.userId];
          if (response == 'yes') return AvailabilityState.available;
          if (response == 'no') return AvailabilityState.notAvailable;
          return AvailabilityState.notResponded;
        },
        onTap: null, // Non-interactive in potential gig mode
        columns: 4,
        buttonHeight: 48, // Slightly taller for two-line names
      ),
    );
  }

  /// Builds a widget for member label, supporting two-line display for disambiguation
  Widget? _buildMemberLabelWidget(MemberVM member, List<MemberVM> allMembers) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);

    // If no disambiguation needed or single-line is sufficient, return null
    // (the grid will use labelBuilder instead)
    if (disambiguation == null || !disambiguation.requiresTwoLines) {
      return null;
    }

    // Two-line display for complex disambiguation (same first + last initial)
    final response = _memberAvailability[member.userId];
    final textColor = (response == 'yes' || response == 'no')
        ? Colors.white
        : AppColors.textSecondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          disambiguation.line1,
          style: AppTextStyles.footnote.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            disambiguation.line2!,
            style: AppTextStyles.navLabel.copyWith(
              color: textColor.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Get display label for a member with disambiguation for duplicate first names
  String _getMemberLabel(MemberVM member, List<MemberVM> allMembers) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null) {
      // Fallback: use full name, truncated if needed
      final name = member.name;
      return name.length > 10 ? '${name.substring(0, 9)}…' : name;
    }
    if (disambiguation.requiresTwoLines) {
      // For two-line display, just return first name (widget builder handles the rest)
      return disambiguation.line1;
    }
    return disambiguation.line1;
  }

  /// Disambiguation result for member name display
  _MemberDisambiguation? _getMemberDisambiguation(
    MemberVM member,
    List<MemberVM> allMembers,
  ) {
    final firstName = member.firstName;

    if (firstName == null || firstName.isEmpty) {
      return null; // Will use fallback in _getMemberLabel
    }

    // Check for duplicate first names
    final sameFirstName = allMembers
        .where((m) => m.firstName == firstName)
        .toList();

    if (sameFirstName.length <= 1) {
      // Unique first name - just use it
      final label = firstName.length > 10
          ? '${firstName.substring(0, 9)}…'
          : firstName;
      return _MemberDisambiguation(line1: label);
    }

    // Multiple members with same first name - need disambiguation
    if (member.lastName == null || member.lastName!.isEmpty) {
      // No last name available, use first name only
      final label = firstName.length > 10
          ? '${firstName.substring(0, 9)}…'
          : firstName;
      return _MemberDisambiguation(line1: label);
    }

    final lastInitial = member.lastName![0].toUpperCase();

    // Check if first name + last initial is unique
    final sameFirstAndInitial = sameFirstName.where((m) {
      final mLastName = m.lastName;
      if (mLastName == null || mLastName.isEmpty) return false;
      return mLastName[0].toUpperCase() == lastInitial;
    }).toList();

    if (sameFirstAndInitial.length <= 1) {
      // First name + last initial is unique: "Alex M."
      final label = '$firstName $lastInitial.';
      return _MemberDisambiguation(
        line1: label.length > 10 ? '${label.substring(0, 9)}…' : label,
      );
    }

    // Same first name AND last initial - use two-line display
    // Line 1: First name
    // Line 2: Full last name (shrinks to fit)
    return _MemberDisambiguation(
      line1: firstName.length > 10
          ? '${firstName.substring(0, 9)}…'
          : firstName,
      line2: member.lastName!,
      requiresTwoLines: true,
    );
  }

  Widget _buildRecurringToggle() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Make this recurring',
            style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          ),
        ),
        Switch.adaptive(
          value: _isRecurring,
          onChanged: _isSaving ? null : _toggleRecurring,
          activeTrackColor: AppColors.accent,
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.textPrimary;
            }
            return null;
          }),
        ),
      ],
    );
  }

  Widget _buildRecurringSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.space16),

        // A) Days of the Week
        Text(
          'Repeat on',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: Weekday.values.map((day) {
            final isSelected = _selectedDays.contains(day);
            return GestureDetector(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        if (isSelected) {
                          _selectedDays.remove(day);
                        } else {
                          _selectedDays.add(day);
                        }
                      });
                      HapticFeedback.selectionClick();
                    },
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : AppColors.scaffoldBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.borderMuted,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  day.shortLabel,
                  style: AppTextStyles.footnote.copyWith(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: Spacing.space16),

        // B) Frequency toggles
        Text(
          'Frequency',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: RecurrenceFrequency.values.map((freq) {
            final isSelected = _frequency == freq;
            return Expanded(
              child: GestureDetector(
                onTap: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _frequency = freq;
                        });
                        HapticFeedback.selectionClick();
                      },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  margin: EdgeInsets.only(
                    right: freq != RecurrenceFrequency.monthly ? 8 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent : AppColors.scaffoldBg,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.borderMuted,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    freq.displayName,
                    style: AppTextStyles.footnote.copyWith(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: Spacing.space16),

        // C) Until date
        Text(
          'Until (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _isSaving ? null : _showUntilDatePicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _untilDate != null
                        ? _formatDateDisplay(_untilDate!)
                        : 'No end date',
                    style: AppTextStyles.callout.copyWith(
                      color: _untilDate != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                if (_untilDate != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _untilDate = null;
                      });
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: Spacing.space16),

        // D) Recurrence Summary with spelled-out day names
        if (_selectedDays.isNotEmpty) ...[
          Text(
            'Summary',
            style: AppTextStyles.footnote.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _buildRecurrenceSummary(),
              style: AppTextStyles.callout.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Build a human-readable recurrence summary with spelled-out day names.
  /// Examples:
  /// - "Weekly on Tuesdays and Thursdays until February 21, 2026"
  /// - "Biweekly on Mondays, Wednesdays, and Fridays"
  /// - "Monthly on Saturdays until March 15, 2026"
  String _buildRecurrenceSummary() {
    if (_selectedDays.isEmpty) return '';

    // Sort days starting from Sunday
    final sortedDays = _selectedDays.toList()
      ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));

    // Map to plural day names
    final dayNames = sortedDays.map((d) => d.pluralName).toList();

    // Natural joining: 2 days = "X and Y", 3+ days = "X, Y, and Z"
    String daysText;
    if (dayNames.length == 1) {
      daysText = dayNames.first;
    } else if (dayNames.length == 2) {
      daysText = '${dayNames[0]} and ${dayNames[1]}';
    } else {
      final allButLast = dayNames.sublist(0, dayNames.length - 1).join(', ');
      daysText = '$allButLast, and ${dayNames.last}';
    }

    final frequencyText = _frequency.displayName;

    String? untilText;
    if (_untilDate != null) {
      untilText = ' until ${_formatFullDate(_untilDate!)}';
    }

    return '$frequencyText on $daysText${untilText ?? ''}';
  }

  /// Format date with full month name (e.g., "February 21, 2026")
  String _formatFullDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _showUntilDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _untilDate ?? _selectedDate.add(const Duration(days: 30)),
      firstDate: _selectedDate,
      lastDate: _selectedDate.add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.cardBg,
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
    }
  }

  /// Bottom action buttons - both equal width (50% each)
  Widget _buildBottomButtons(double safeBottom, double keyboardHeight) {
    // In create mode, also check if required fields are filled
    // In edit mode, disable the button until changes are made
    final canSave = !_isSaving && !_isDeleting && _hasChanges && _isFormValid;

    return Container(
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: Spacing.space12,
        bottom: safeBottom + keyboardHeight + Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(
          top: BorderSide(color: AppColors.borderMuted.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Cancel button - equal width
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: (_isSaving || _isDeleting)
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onCancelled?.call();
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.borderMuted),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.calloutEmphasized.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.space12),
          // Primary button - equal width
          Expanded(
            child: BrandActionButton(
              label: _primaryButtonLabel,
              isLoading: _isSaving,
              onPressed: canSave ? _handleSave : null,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // SETLIST SELECTOR
  // ============================================================================

  /// Builds the setlist selector row with horizontal scrolling pills
  Widget _buildSetlistSelector() {
    final setlistsState = ref.watch(setlistsProvider);
    final setlists = setlistsState.setlists;
    final isLoading = setlistsState.isLoading;
    final error = setlistsState.error;

    // Filter to get only user-created setlists (excludes Catalog)
    final userSetlists = _sortSetlists(setlists);
    final hasNoSetlists = userSetlists.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Setlist',
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),

        // Loading state
        if (isLoading)
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading setlists...',
                  style: AppTextStyles.footnote.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          )
        // Error state
        else if (error != null && setlists.isEmpty)
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            child: Text(
              "Couldn't load setlists",
              style: AppTextStyles.footnote.copyWith(color: AppColors.error),
            ),
          )
        // Normal state: horizontal scrollable pills
        else
          SizedBox(
            height: 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // "None" pill - always first
                  _buildSetlistPill(
                    id: null,
                    name: 'None',
                    isSelected: _selectedSetlistId == null,
                  ),
                  const SizedBox(width: 8),

                  // If no setlists exist, show "+ Create Setlist" link
                  if (hasNoSetlists)
                    GestureDetector(
                      onTap: _isSaving ? null : _navigateToCreateSetlist,
                      child: Text(
                        '+ Create Setlist',
                        style: AppTextStyles.footnote.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  // Setlist pills - alphabetical (Catalog already excluded by _sortSetlists)
                  else
                    ...userSetlists.map((setlist) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildSetlistPill(
                          id: setlist.id,
                          name: setlist.name,
                          isSelected: _selectedSetlistId == setlist.id,
                          isCatalog: setlist.isCatalog,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Navigate to create a new setlist
  void _navigateToCreateSetlist() {
    // Close the drawer first
    Navigator.of(context).pop();
    // Navigate to new setlist screen
    Navigator.of(context).push(fadeSlideRoute(page: const NewSetlistScreen()));
  }

  /// Sort setlists: alphabetical by name (Catalog excluded)
  List<Setlist> _sortSetlists(List<Setlist> setlists) {
    // Filter out Catalog - it's not a valid option for events
    final filtered = setlists.where((s) => !s.isCatalog).toList();
    // Sort alphabetically
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  /// Build an individual setlist pill/toggle button
  Widget _buildSetlistPill({
    required String? id,
    required String name,
    required bool isSelected,
    bool isCatalog = false,
  }) {
    return GestureDetector(
      onTap: _isSaving
          ? null
          : () {
              setState(() {
                if (id == null) {
                  // "None" selected
                  _selectedSetlistId = null;
                  _selectedSetlistName = null;
                } else {
                  _selectedSetlistId = id;
                  _selectedSetlistName = name;
                }
              });
              HapticFeedback.selectionClick();
            },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.scaffoldBg,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.borderMuted,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCatalog) ...[
              Icon(
                Icons.library_music_rounded,
                size: 14,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              name,
              style: AppTextStyles.footnote.copyWith(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the gig pay input field with POS-style currency entry
  Widget _buildGigPayField() {
    return CurrencyTextField(
      controller: _gigPayController,
      label: 'Gig Pay (optional)',
      hint: '\$0.00',
      enabled: !_isSaving,
      onChanged: () => setState(() {}),
    );
  }
}

// ============================================================================
// AVAILABILITY BUTTON
// YES/NO button for user's potential gig availability response
// ============================================================================

/// Availability response button with animated state transitions.
/// Smoothly animates between selected/unselected states.
class _AvailabilityButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isPositive;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AvailabilityButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isPositive,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isPositive
        ? const Color(0xFF22C55E) // green-500
        : const Color(0xFFEF4444); // red-500

    final backgroundColor = isSelected
        ? activeColor.withValues(alpha: 0.2)
        : AppColors.scaffoldBg;

    final borderColor = isSelected ? activeColor : AppColors.borderMuted;

    final contentColor = isSelected ? activeColor : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          // Animate background and border color changes for smooth state transitions
          duration: AppDurations.fast,
          curve: AppCurves.ease,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: activeColor,
                    ),
                  )
                : AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Row(
                      key: ValueKey('$label-$isSelected'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 20, color: contentColor),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: contentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Helper class for member name disambiguation
class _MemberDisambiguation {
  final String line1;
  final String? line2;
  final bool requiresTwoLines;

  const _MemberDisambiguation({
    required this.line1,
    this.line2,
    this.requiresTwoLines = false,
  });
}
