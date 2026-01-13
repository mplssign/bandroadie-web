import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/models/user_profile.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/utils/phone_formatter.dart';
import '../../components/ui/brand_action_button.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../members/members_controller.dart';
import '../members/members_repository.dart';
import 'user_band_roles_repository.dart';

// ============================================================================
// MY PROFILE SCREEN
// Full profile editor with birthday picker, role pills, and dirty-state save.
// Matches Figma spec with Rose/500 accent and dark theme.
//
// BAND SCOPING: Custom roles are stored per-band in the band_roles table.
// ============================================================================

/// Design tokens for this screen
class _ProfileTokens {
  _ProfileTokens._();

  // Colors
  static const Color accent = Color(0xFFBE123C); // rose-700
  static const Color background = Color(0xFF1E1E1E);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color borderMuted = Color(0xFF334155);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF64748B);

  // Pill styling
  static const double pillHeight = 36.0;
  static const double pillRadius = 18.0;
  static const double dayCircleSize = 40.0;

  // Typography
  static const TextStyle titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.25,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle smallLabelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle pillTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static const TextStyle dayTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

/// Predefined role options
const List<String> _predefinedRoles = [
  'Lead Vocals',
  'Guitar',
  'Bass',
  'Drums',
  'Keyboard',
  'Piano',
  'Sound',
  'DJ',
  'Backing Vocals',
  'Lead Guitar',
  'Rhythm Guitar',
  'Percussion',
  'Acoustic Guitar',
];

/// Month abbreviations
const List<String> _monthAbbreviations = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Full month names for display
const List<String> _fullMonthNames = [
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

/// Days in each month
/// February always returns 29 to support leap year birthdays
int _getDaysInMonth(int monthIndex) {
  const daysPerMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (monthIndex < 0 || monthIndex >= 12) return 31;
  return daysPerMonth[monthIndex];
}

class MyProfileScreen extends ConsumerStatefulWidget {
  /// When true, user cannot navigate away until profile is complete
  final bool isGated;

  /// Callback when profile is saved successfully (used in gated mode)
  final VoidCallback? onProfileComplete;

  /// Callback when user chooses to skip profile completion (used in gated mode)
  final VoidCallback? onSkip;

  const MyProfileScreen({
    super.key,
    this.isGated = false,
    this.onProfileComplete,
    this.onSkip,
  });

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _zipController = TextEditingController();

  // Birthday state
  int? _selectedMonth; // 0-11
  int? _selectedDay; // 1-31

  // Roles state
  Set<String> _selectedRoles = {};
  List<String> _bandCustomRoles = []; // Custom roles for active band from DB
  Set<String> _originalBandCustomRoles = {}; // Track original for dirty check

  // Original values for dirty checking
  String? _originalFirstName;
  String? _originalLastName;
  String? _originalPhone;
  String? _originalAddress;
  String? _originalZip;
  int? _originalMonth;
  int? _originalDay;
  Set<String> _originalRoles = {};

  // UI state
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  // Phone validation state
  String? _phoneErrorText;
  bool _hasAttemptedSave = false;

  // Role delete mode
  bool _isDeleteMode = false;

  // Multi-band support
  List<Band> _userBands = []; // All bands user belongs to
  String?
  _selectedBandId; // Currently selected band for role editing (multi-band mode)
  Map<String, Set<String>> _bandRolesMap = {}; // bandId -> selected roles
  Map<String, Set<String>> _originalBandRolesMap =
      {}; // Original for dirty checking

  /// Whether we're in multi-band mode (user has 2+ bands)
  bool get _isMultiBandMode => _userBands.length >= 2;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _loadError = 'Not logged in';
          _isLoading = false;
        });
        return;
      }

      // Get active band ID from provider
      final bandState = ref.read(activeBandProvider);
      _userBands = bandState.userBands;

      final response = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // New user with no profile record yet - show empty form
      if (response == null) {
        debugPrint(
          '[MyProfileScreen] No profile found for user $userId - showing empty form',
        );
        // Set original values to empty for dirty checking
        _originalFirstName = '';
        _originalLastName = '';
        _originalPhone = '';
        _originalAddress = '';
        _originalZip = '';
        _originalMonth = null;
        _originalDay = null;
        _originalRoles = {};

        setState(() {
          _isLoading = false;
        });
        return;
      }

      final profile = UserProfile.fromJson(response);

      // Populate form fields
      _firstNameController.text = profile.firstName ?? '';
      _lastNameController.text = profile.lastName ?? '';
      // Format phone number for display (stored as raw digits)
      _phoneController.text = formatPhoneNumber(profile.phone ?? '');
      _addressController.text = profile.address ?? '';
      _zipController.text = profile.zip ?? '';

      // Birthday
      if (profile.birthday != null) {
        _selectedMonth = profile.birthday!.month - 1;
        _selectedDay = profile.birthday!.day;
      }

      // Load user's global roles from profile (used for single-band mode or fallback)
      _selectedRoles = Set.from(profile.roles);

      // Initialize multi-band mode if applicable
      if (_isMultiBandMode) {
        await _initializeMultiBandRoles(userId, profile.roles);
      }

      // Extract custom roles from selected roles (roles not in predefined list)
      _extractCustomRolesFromSelected();

      // Store originals for dirty checking
      _originalFirstName = _firstNameController.text;
      _originalLastName = _lastNameController.text;
      _originalPhone = _phoneController.text;
      _originalAddress = _addressController.text;
      _originalZip = _zipController.text;
      _originalMonth = _selectedMonth;
      _originalDay = _selectedDay;
      _originalRoles = Set.from(_selectedRoles);
      _originalBandCustomRoles = Set.from(_bandCustomRoles);
      // Deep copy band roles map for dirty checking
      _originalBandRolesMap = _bandRolesMap.map(
        (key, value) => MapEntry(key, Set.from(value)),
      );

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Initialize roles for multi-band mode
  /// Loads band-specific roles and seeds from global roles if needed
  Future<void> _initializeMultiBandRoles(
    String userId,
    List<String> globalRoles,
  ) async {
    final repo = ref.read(userBandRolesRepositoryProvider);
    final bandIds = _userBands.map((b) => b.id).toList();

    // Batch fetch existing band-specific roles
    final existingRoles = await repo.fetchRolesForBands(
      bandIds: bandIds,
      userId: userId,
    );

    // Initialize band roles map
    _bandRolesMap = {};

    for (final band in _userBands) {
      if (existingRoles.containsKey(band.id)) {
        // Use existing band-specific roles
        _bandRolesMap[band.id] = Set.from(existingRoles[band.id]!);
      } else {
        // Seed from global roles (first time access)
        _bandRolesMap[band.id] = Set.from(globalRoles);
        // Persist the seeded roles
        await repo.upsertRolesForBand(
          bandId: band.id,
          userId: userId,
          roles: globalRoles,
        );
      }
    }

    // Set selected band (first band in switcher order = first in list)
    if (_userBands.isNotEmpty) {
      _selectedBandId = _userBands.first.id;
      // Set _selectedRoles to match the selected band's roles
      _selectedRoles = Set.from(_bandRolesMap[_selectedBandId] ?? {});
    }
  }

  /// Extract custom roles from a set of roles
  /// Custom roles are any roles that aren't in _predefinedRoles
  void _extractCustomRolesFromSelected() {
    final customRoles = <String>[];
    for (final role in _selectedRoles) {
      if (!_predefinedRoles.contains(role) && !customRoles.contains(role)) {
        customRoles.add(role);
      }
    }
    _bandCustomRoles = customRoles;
  }

  /// Validate US ZIP code format (5 digits or ZIP+4 format)
  /// Returns null if valid or empty, error message if invalid
  String? _validateZipCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Empty is valid (optional field)
    }
    final trimmed = value.trim();
    // US ZIP: 5 digits or ZIP+4 (12345 or 12345-6789)
    final zipPattern = RegExp(r'^\d{5}(-\d{4})?$');
    if (!zipPattern.hasMatch(trimmed)) {
      return 'Enter valid ZIP (12345 or 12345-6789)';
    }
    return null;
  }

  bool get _isDirty {
    if (_firstNameController.text != _originalFirstName) return true;
    if (_lastNameController.text != _originalLastName) return true;
    if (_phoneController.text != _originalPhone) return true;
    if (_addressController.text != _originalAddress) return true;
    if (_zipController.text != _originalZip) return true;
    if (_selectedMonth != _originalMonth) return true;
    if (_selectedDay != _originalDay) return true;

    // In multi-band mode, check all band roles
    if (_isMultiBandMode) {
      for (final bandId in _bandRolesMap.keys) {
        final current = _bandRolesMap[bandId] ?? {};
        final original = _originalBandRolesMap[bandId] ?? {};
        if (!_setEquals(current, original)) return true;
      }
    } else {
      // Single-band mode: check global roles
      if (!_setEquals(_selectedRoles, _originalRoles)) return true;
    }

    // Check if custom roles have been added
    if (!_setEquals(Set.from(_bandCustomRoles), _originalBandCustomRoles)) {
      return true;
    }
    return false;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  void _onMonthSelected(int monthIndex) {
    setState(() {
      _selectedMonth = monthIndex;
      // Clear day if it's invalid for new month
      if (_selectedDay != null) {
        final maxDays = _getDaysInMonth(monthIndex);
        if (_selectedDay! > maxDays) {
          _selectedDay = null;
        }
      }
    });
  }

  void _onDaySelected(int day) {
    setState(() => _selectedDay = day);
  }

  void _toggleRole(String role) {
    setState(() {
      if (_selectedRoles.contains(role)) {
        _selectedRoles.remove(role);
      } else {
        _selectedRoles.add(role);
      }

      // In multi-band mode, also update the band roles map
      if (_isMultiBandMode && _selectedBandId != null) {
        _bandRolesMap[_selectedBandId!] = Set.from(_selectedRoles);
      }
    });
  }

  /// Switch to a different band in multi-band mode
  void _onBandSelected(String bandId) {
    if (bandId == _selectedBandId) return;

    setState(() {
      _selectedBandId = bandId;
      // Load the selected band's roles into _selectedRoles
      _selectedRoles = Set.from(_bandRolesMap[bandId] ?? {});
      // Update custom roles to match this band's selected roles
      _extractCustomRolesFromSelected();
    });
  }

  Future<void> _showAddRoleDialog() async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _ProfileTokens.surfaceDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Add custom role',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _ProfileTokens.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a custom role to add to your roles list.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: _ProfileTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: _ProfileTokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. Rhythm Guitar',
                    hintStyle: const TextStyle(color: _ProfileTokens.textMuted),
                    errorText: errorText,
                    filled: true,
                    fillColor: _ProfileTokens.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: _ProfileTokens.borderMuted,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: _ProfileTokens.borderMuted,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: _ProfileTokens.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  onSubmitted: (value) {
                    _validateAndSubmitRole(
                      value,
                      setDialogState,
                      (error) => errorText = error,
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: _ProfileTokens.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () {
                  _validateAndSubmitRole(
                    controller.text,
                    setDialogState,
                    (error) => errorText = error,
                  );
                },
                child: const Text(
                  'Add',
                  style: TextStyle(
                    color: _ProfileTokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result.isNotEmpty) {
      _addCustomRole(result);
    }
  }

  void _validateAndSubmitRole(
    String value,
    StateSetter setDialogState,
    void Function(String?) setError,
  ) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setDialogState(() => setError('Please enter a role'));
      return;
    }
    // Check for duplicates (case-insensitive) among predefined + band custom roles
    final allRoles = [..._predefinedRoles, ..._bandCustomRoles];
    final isDuplicate = allRoles.any(
      (r) => r.toLowerCase() == trimmed.toLowerCase(),
    );
    if (isDuplicate) {
      setDialogState(() => setError('Role already exists'));
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  /// Add a custom role and select it
  /// Custom roles are stored directly in user_band_roles.roles[] alongside predefined roles
  void _addCustomRole(String roleLabel) {
    // Just add to local state - will be saved with the profile
    setState(() {
      // Track as custom role for display purposes - insert at beginning
      if (!_bandCustomRoles.contains(roleLabel)) {
        _bandCustomRoles.insert(0, roleLabel);
      }
      _selectedRoles.add(roleLabel);

      // In multi-band mode, also update the band roles map
      if (_isMultiBandMode && _selectedBandId != null) {
        _bandRolesMap[_selectedBandId!] = Set.from(_selectedRoles);
      }
    });
  }

  /// Delete a custom role (only user-created roles can be deleted)
  /// Removes the role from selection, from the custom roles list, and persists to database.
  ///
  /// BUG FIX: Previously, this method only updated local state but did not persist
  /// the change to the database. When the user navigated away and returned, the role
  /// would reappear because it was reloaded from the unchanged database state.
  /// Now we persist the role removal immediately after updating local state.
  Future<void> _deleteCustomRole(String roleLabel) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ProfileTokens.surfaceDark,
        title: const Text(
          'Delete Role',
          style: TextStyle(color: _ProfileTokens.textPrimary),
        ),
        content: Text(
          'Remove "$roleLabel" from your roles?',
          style: const TextStyle(color: _ProfileTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _ProfileTokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: _ProfileTokens.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Update local state first (optimistic UI)
    setState(() {
      // Remove from custom roles list
      _bandCustomRoles.remove(roleLabel);
      // Unselect the role
      _selectedRoles.remove(roleLabel);

      // In multi-band mode, also update the band roles map
      if (_isMultiBandMode && _selectedBandId != null) {
        _bandRolesMap[_selectedBandId!] = Set.from(_selectedRoles);
      }
    });

    // Persist the change to the database
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final repo = ref.read(userBandRolesRepositoryProvider);
      final activeBandId = ref.read(activeBandProvider).activeBandId;

      if (_isMultiBandMode && _selectedBandId != null) {
        // Multi-band mode: update roles for the selected band
        await repo.upsertRolesForBand(
          bandId: _selectedBandId!,
          userId: userId,
          roles: _selectedRoles.toList(),
        );
      } else if (activeBandId != null) {
        // Single-band mode: update roles for the active band
        await repo.upsertRolesForBand(
          bandId: activeBandId,
          userId: userId,
          roles: _selectedRoles.toList(),
        );
      }

      // Also update global roles in users table for backward compatibility
      await supabase
          .from('users')
          .update({
            'roles': _selectedRoles.toList(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // Update originals to reflect saved state (prevents dirty state issues)
      _originalRoles = Set.from(_selectedRoles);
      _originalBandCustomRoles = Set.from(_bandCustomRoles);
      if (_isMultiBandMode && _selectedBandId != null) {
        _originalBandRolesMap[_selectedBandId!] = Set.from(_selectedRoles);
      }

      // Clear caches and refresh members to reflect the change
      ref.read(userBandRolesRepositoryProvider).clearCache();
      ref.read(membersRepositoryProvider).clearAllCaches();
      if (activeBandId != null) {
        ref
            .read(membersProvider.notifier)
            .loadMembers(activeBandId, forceRefresh: true);
      }

      if (mounted) {
        showSuccessSnackBar(context, message: 'Role "$roleLabel" removed');
      }
    } catch (e) {
      // Rollback optimistic UI on failure
      if (mounted) {
        setState(() {
          // Re-add the role back
          _bandCustomRoles.add(roleLabel);
          _selectedRoles.add(roleLabel);
          if (_isMultiBandMode && _selectedBandId != null) {
            _bandRolesMap[_selectedBandId!] = Set.from(_selectedRoles);
          }
        });
        showErrorSnackBar(context, message: 'Failed to remove role');
        debugPrint('[MyProfileScreen] Role deletion failed: $e');
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _hasAttemptedSave = true);

    if (!_formKey.currentState!.validate()) return;

    // Validate phone number if provided
    final phoneText = _phoneController.text.trim();
    if (phoneText.isNotEmpty && !isValidUsPhone(phoneText)) {
      setState(() => _phoneErrorText = 'Invalid phone number');
      showErrorSnackBar(
        context,
        message: 'Fix your phone number and try again.',
      );
      return;
    }
    setState(() => _phoneErrorText = null);

    // Roles are optional - no validation required
    // Users can proceed without selecting any roles

    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // Build birthday string if both month and day are selected
      String? birthdayStr;
      if (_selectedMonth != null && _selectedDay != null) {
        // Use a fixed year (2000) since we only store month/day
        final month = (_selectedMonth! + 1).toString().padLeft(2, '0');
        final day = _selectedDay!.toString().padLeft(2, '0');
        birthdayStr = '2000-$month-$day';
      }

      // ALWAYS save band-specific roles to user_band_roles table
      // This ensures Members page always has the correct data
      // (Members page reads from user_band_roles first, falls back to users.roles)
      final repo = ref.read(userBandRolesRepositoryProvider);
      final activeBandId = ref.read(activeBandProvider).activeBandId;

      if (_isMultiBandMode) {
        // Multi-band mode: save roles for each band that has changed
        for (final entry in _bandRolesMap.entries) {
          final bandId = entry.key;
          final currentRoles = entry.value;
          final originalRoles = _originalBandRolesMap[bandId] ?? {};

          if (!_setEquals(currentRoles, originalRoles)) {
            await repo.upsertRolesForBand(
              bandId: bandId,
              userId: userId,
              roles: currentRoles.toList(),
            );
          }
        }
      } else if (activeBandId != null) {
        // Single-band mode: always save to user_band_roles for the active band
        // This ensures consistency with how Members page reads roles
        await repo.upsertRolesForBand(
          bandId: activeBandId,
          userId: userId,
          roles: _selectedRoles.toList(),
        );
      }

      // Always update the users table with basic profile info
      // Also keep global roles in sync for backward compatibility
      // Use upsert to handle both new users and existing users
      final userEmail = supabase.auth.currentUser?.email ?? '';
      await supabase.from('users').upsert({
        'id': userId,
        'email': userEmail,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': normalizePhoneForStorage(_phoneController.text),
        'address': _addressController.text.trim(),
        'zip': _zipController.text.trim(),
        'birthday': birthdayStr,
        // Always sync global roles for backward compatibility
        'roles': _selectedRoles.toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Update originals to reflect saved state
      _originalFirstName = _firstNameController.text;
      _originalLastName = _lastNameController.text;
      _originalPhone = _phoneController.text;
      _originalAddress = _addressController.text;
      _originalZip = _zipController.text;
      _originalMonth = _selectedMonth;
      _originalDay = _selectedDay;
      _originalRoles = Set.from(_selectedRoles);
      _originalBandCustomRoles = Set.from(_bandCustomRoles);
      // Deep copy band roles map for dirty checking
      _originalBandRolesMap = _bandRolesMap.map(
        (key, value) => MapEntry(key, Set.from(value)),
      );

      // =========================================
      // BUST CACHES + REFRESH MEMBERS (CRITICAL)
      // Ensures Members screen shows updated roles after save.
      //
      // DATA FLOW FIX:
      // Previously, cache clearing was done on new repository instances,
      // which didn't affect the actual cached data used by Members screen.
      // Now we use the provider-based repository for consistent caching.
      // =========================================

      // Debug log per requirements
      if (kDebugMode) {
        final savedRoles = _isMultiBandMode && activeBandId != null
            ? (_bandRolesMap[activeBandId] ?? {}).toList()
            : _selectedRoles.toList();
        debugPrint(
          '[MyProfileScreen] Saved roles for user=$userId band=$activeBandId roles=$savedRoles',
        );
      }

      // 1. Clear user_band_roles cache (shared via provider)
      ref.read(userBandRolesRepositoryProvider).clearCache();

      // 2. Clear members repository cache via the provider
      // This also clears the internal user_band_roles cache for consistency.
      // Using the provider ensures we clear the SAME instance used by MembersNotifier.
      ref.read(membersRepositoryProvider).clearAllCaches();

      // 3. Force reload members for the active band
      // forceRefresh bypasses the cache and fetches fresh data from the database.
      if (activeBandId != null) {
        ref
            .read(membersProvider.notifier)
            .loadMembers(activeBandId, forceRefresh: true);
      }

      setState(() => _isSaving = false);

      if (mounted) {
        showSuccessSnackBar(context, message: 'Profile saved successfully');

        // In gated mode, notify parent that profile is complete
        if (widget.isGated && widget.onProfileComplete != null) {
          widget.onProfileComplete!();
        } else {
          // Navigate back to Dashboard after successful save
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showErrorSnackBar(context, message: 'Error: $e');
      }
    }
  }

  void _cancel() {
    // Revert to original values
    _firstNameController.text = _originalFirstName ?? '';
    _lastNameController.text = _originalLastName ?? '';
    _phoneController.text = _originalPhone ?? '';
    _addressController.text = _originalAddress ?? '';
    _zipController.text = _originalZip ?? '';
    setState(() {
      _selectedMonth = _originalMonth;
      _selectedDay = _originalDay;
      _selectedRoles = Set.from(_originalRoles);
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileTokens.background,
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        title: Text(
          widget.isGated ? 'Complete Your Profile' : 'My Profile',
          style: _ProfileTokens.titleStyle,
        ),
        automaticallyImplyLeading: false,
        leading: widget.isGated
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _ProfileTokens.accent),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'Error loading profile',
                style: _ProfileTokens.titleStyle,
              ),
              const SizedBox(height: 8),
              Text(
                _loadError!,
                style: _ProfileTokens.subtitleStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              BrandActionButton(label: 'Retry', onPressed: _loadProfile),
            ],
          ),
        ),
      );
    }

    return _buildForm();
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subtitle
                  Text(
                    widget.isGated
                        ? 'Please complete your profile to continue'
                        : 'Update your personal information',
                    style: _ProfileTokens.subtitleStyle,
                  ),
                  const SizedBox(height: 24),

                  // ROW 1: First Name + Last Name = 2 columns side-by-side
                  _buildTwoCol(
                    _buildTextField(
                      controller: _firstNameController,
                      label: 'First Name',
                    ),
                    _buildTextField(
                      controller: _lastNameController,
                      label: 'Last Name',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ROW 2: Phone Number = full width (single field row)
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    hint: '(312) 550-7844',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneNumberInputFormatter()],
                    errorText: _phoneErrorText,
                    onChanged: (value) {
                      // Clear error once phone becomes valid (only if user already tried saving)
                      if (_hasAttemptedSave && isValidUsPhone(value)) {
                        setState(() => _phoneErrorText = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // ROW 3: Address + Zip Code = 2 columns side-by-side
                  _buildTwoCol(
                    _buildTextField(
                      controller: _addressController,
                      label: 'Address',
                    ),
                    _buildTextField(
                      controller: _zipController,
                      label: 'Zip Code',
                      keyboardType: TextInputType.number,
                      customValidator: _validateZipCode,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Birthday Section
                  _buildBirthdaySection(),
                  const SizedBox(height: 32),

                  // Role in Band Section
                  _buildRoleSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Footer with Save / Cancel
          _buildFooter(),
        ],
      ),
    );
  }

  /// Two-column layout helper - always side-by-side
  Widget _buildTwoCol(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    ValueChanged<String>? onChanged,
    String? Function(String?)? customValidator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: _ProfileTokens.labelStyle,
            children: isRequired
                ? [
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: _ProfileTokens.accent),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: _ProfileTokens.textPrimary),
          onChanged: (value) {
            setState(() {}); // Trigger dirty check
            onChanged?.call(value);
          },
          validator:
              customValidator ??
              (isRequired
                  ? (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '$label is required';
                      }
                      return null;
                    }
                  : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _ProfileTokens.textMuted),
            errorText: errorText,
            filled: true,
            fillColor: _ProfileTokens.surfaceDark,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _ProfileTokens.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _ProfileTokens.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: _ProfileTokens.accent,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBirthdaySection() {
    // Compute selected birthday label if both month and day are selected
    String? selectedBirthdayLabel;
    if (_selectedMonth != null && _selectedDay != null) {
      selectedBirthdayLabel =
          '${_fullMonthNames[_selectedMonth!]} $_selectedDay';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Birthday label with inline selected date
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Birthday', style: _ProfileTokens.labelStyle),
            if (selectedBirthdayLabel != null) ...[
              const SizedBox(width: 8),
              Text(
                selectedBirthdayLabel,
                style: _ProfileTokens.labelStyle.copyWith(
                  color: _ProfileTokens.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Month subsection
        const Text('Month', style: _ProfileTokens.smallLabelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(12, (index) {
            final isSelected = _selectedMonth == index;
            return _MonthPill(
              label: _monthAbbreviations[index],
              isSelected: isSelected,
              onTap: () => _onMonthSelected(index),
            );
          }),
        ),
        const SizedBox(height: 16),

        // Day subsection
        const Text('Day', style: _ProfileTokens.smallLabelStyle),
        const SizedBox(height: 8),
        _selectedMonth == null
            ? const Text(
                'Select a month first',
                style: TextStyle(
                  color: _ProfileTokens.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_getDaysInMonth(_selectedMonth!), (
                  index,
                ) {
                  final day = index + 1;
                  final isSelected = _selectedDay == day;
                  return _DayCircle(
                    day: day,
                    isSelected: isSelected,
                    onTap: () => _onDaySelected(day),
                  );
                }),
              ),
      ],
    );
  }

  /// Toggle delete mode for roles
  void _toggleDeleteMode() {
    setState(() {
      _isDeleteMode = !_isDeleteMode;
    });
  }

  Widget _buildRoleSection() {
    // Build the list of all role pills with control buttons, spacing, and roles
    final allRolePills = <Widget>[
      // Control buttons: + Add and Remove
      _RolePill(
        label: '+ Add',
        isSelected: false,
        isAddButton: true,
        onTap: () {
          // Exit delete mode when adding
          if (_isDeleteMode) {
            setState(() => _isDeleteMode = false);
          }
          _showAddRoleDialog();
        },
      ),
      _RolePill(
        label: _isDeleteMode ? 'Done' : 'Remove',
        isSelected: _isDeleteMode,
        isRemoveButton: true,
        onTap: _toggleDeleteMode,
      ),
      // Extra spacing (2x default) after control buttons
      const SizedBox(
        width: 16,
      ), // Additional 8px beyond the normal 8px = 16px gap
      // Custom roles first (user-created, shown at beginning)
      ..._bandCustomRoles.map(
        (role) => _RolePill(
          label: role,
          isSelected: _selectedRoles.contains(role),
          isCustomRole: true,
          showDeleteIcon: _isDeleteMode,
          onTap: _isDeleteMode
              ? () => _deleteCustomRole(role)
              : () => _toggleRole(role),
        ),
      ),
      // Predefined roles (also deletable in delete mode)
      ..._predefinedRoles.map(
        (role) => _RolePill(
          label: role,
          isSelected: _selectedRoles.contains(role),
          showDeleteIcon: _isDeleteMode,
          onTap: _isDeleteMode
              ? () => _deleteCustomRole(role)
              : () => _toggleRole(role),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Role in Band', style: _ProfileTokens.labelStyle),

        // Band selector row - only shown in multi-band mode
        if (_isMultiBandMode) ...[
          const SizedBox(height: 12),
          const Text('Select Band', style: _ProfileTokens.smallLabelStyle),
          const SizedBox(height: 8),
          SizedBox(
            height: _ProfileTokens.pillHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _userBands
                    .map(
                      (band) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _BandPill(
                          label: band.name,
                          isSelected: _selectedBandId == band.id,
                          onTap: () => _onBandSelected(band.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),
        // Single horizontal scrollable row (no wrapping)
        SizedBox(
          height: _ProfileTokens.pillHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  allRolePills
                      .expand((widget) => [widget, const SizedBox(width: 8)])
                      .toList()
                    ..removeLast(), // Remove trailing spacer
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: _ProfileTokens.background,
        border: Border(top: BorderSide(color: _ProfileTokens.borderMuted)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons row - Cancel (secondary) and Save (primary) side by side
            // Cancel is hidden in gated mode (first-time profile completion)
            Row(
              children: [
                // Cancel button - secondary action on the left (non-gated mode)
                if (!widget.isGated) ...[
                  Expanded(
                    child: TextButton(
                      onPressed: _cancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _ProfileTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                // Skip for now button - secondary action on the left (gated mode only)
                if (widget.isGated && widget.onSkip != null) ...[
                  Expanded(
                    child: TextButton(
                      onPressed: widget.onSkip,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _ProfileTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                // Save Profile button - primary action on the right
                Expanded(
                  flex: (widget.isGated && widget.onSkip != null)
                      ? 2
                      : (widget.isGated ? 1 : 2),
                  child: BrandActionButton(
                    label: 'Save Profile',
                    fullWidth: true,
                    isLoading: _isSaving,
                    onPressed: _isDirty && !_isSaving ? _saveProfile : null,
                  ),
                ),
              ],
            ),
            // Helper text for gated mode - inform users they can complete profile later
            if (widget.isGated) ...[
              const SizedBox(height: 16),
              const Text(
                'You can complete your profile later in the menu.',
                style: TextStyle(
                  fontSize: 14,
                  color: _ProfileTokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MONTH PILL WIDGET
// ============================================================================

class _MonthPill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MonthPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_MonthPill> createState() => _MonthPillState();
}

class _MonthPillState extends State<_MonthPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _ProfileTokens.pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? _ProfileTokens.accent
                : Colors.transparent,
            borderRadius: BorderRadius.circular(_ProfileTokens.pillRadius),
            border: Border.all(
              color: widget.isSelected
                  ? _ProfileTokens.accent
                  : _ProfileTokens.borderMuted,
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1.0,
            child: Text(
              widget.label,
              style: _ProfileTokens.pillTextStyle.copyWith(
                color: widget.isSelected
                    ? Colors.white
                    : _ProfileTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DAY CIRCLE WIDGET
// ============================================================================

class _DayCircle extends StatefulWidget {
  final int day;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayCircle({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_DayCircle> createState() => _DayCircleState();
}

class _DayCircleState extends State<_DayCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _ProfileTokens.dayCircleSize,
          height: _ProfileTokens.dayCircleSize,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? _ProfileTokens.accent
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isSelected
                  ? _ProfileTokens.accent
                  : _ProfileTokens.borderMuted,
            ),
          ),
          child: Center(
            child: Text(
              widget.day.toString(),
              style: _ProfileTokens.dayTextStyle.copyWith(
                color: widget.isSelected
                    ? Colors.white
                    : _ProfileTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ROLE PILL WIDGET
// ============================================================================

class _RolePill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isAddButton;
  final bool isRemoveButton;
  final bool isCustomRole;
  final bool showDeleteIcon;
  final VoidCallback? onTap;

  const _RolePill({
    required this.label,
    required this.isSelected,
    this.isAddButton = false,
    this.isRemoveButton = false,
    this.isCustomRole = false,
    this.showDeleteIcon = false,
    this.onTap,
  });

  @override
  State<_RolePill> createState() => _RolePillState();
}

class _RolePillState extends State<_RolePill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAddButton = widget.isAddButton;
    final isRemoveButton = widget.isRemoveButton;
    final isCustomRole = widget.isCustomRole;

    // Rose 600 from Tailwind for action buttons
    const rose600 = Color(0xFFE11D48);

    // Determine border color
    Color borderColor;
    if (isAddButton || isRemoveButton) {
      borderColor = rose600;
    } else if (isCustomRole) {
      borderColor = const Color(0xFF6366F1); // Indigo for custom roles
    } else if (widget.isSelected) {
      borderColor = _ProfileTokens.accent;
    } else {
      borderColor = _ProfileTokens.borderMuted;
    }

    // Determine text color
    Color textColor;
    if (isAddButton || isRemoveButton) {
      textColor = widget.isSelected ? Colors.white : rose600;
    } else if (widget.isSelected) {
      textColor = Colors.white;
    } else {
      textColor = _ProfileTokens.textSecondary;
    }

    // Determine background color
    Color bgColor;
    if (isRemoveButton && widget.isSelected) {
      bgColor = rose600; // Filled rose when in delete mode
    } else if (widget.isSelected && !isAddButton) {
      bgColor = _ProfileTokens.accent;
    } else {
      bgColor = Colors.transparent;
    }

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _ProfileTokens.pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(_ProfileTokens.pillRadius),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show X icon for roles in delete mode
                if (widget.showDeleteIcon) ...[
                  Icon(Icons.close, size: 14, color: const Color(0xFFEF4444)),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: _ProfileTokens.pillTextStyle.copyWith(
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// BAND PILL WIDGET
// For selecting which band to edit roles for in multi-band mode
// ============================================================================

class _BandPill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BandPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_BandPill> createState() => _BandPillState();
}

class _BandPillState extends State<_BandPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rose 600 from Tailwind
    const rose600 = Color(0xFFE11D48);

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _ProfileTokens.pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.isSelected ? rose600 : Colors.transparent,
            borderRadius: BorderRadius.circular(_ProfileTokens.pillRadius),
            border: Border.all(color: rose600, width: 1),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: _ProfileTokens.pillTextStyle.copyWith(
                color: widget.isSelected ? Colors.white : rose600,
                fontWeight: widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
