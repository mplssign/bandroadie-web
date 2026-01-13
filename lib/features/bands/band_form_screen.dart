import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../components/ui/brand_action_button.dart';
import '../../components/ui/field_hint.dart';
import '../../components/ui/frosted_glass_bar.dart';
import '../../shared/utils/initials.dart';
import '../../shared/utils/snackbar_helper.dart';
import 'active_band_controller.dart';
import 'widgets/band_avatar.dart';

// ============================================================================
// BAND FORM SCREEN - Shared screen for Create and Edit Band flows
// ============================================================================

/// Mode for the band form
enum BandFormMode { create, edit }

/// Available avatar colors matching the Figma design
class AvatarColors {
  AvatarColors._();

  static const List<AvatarColorOption> colors = [
    AvatarColorOption('bg-rose-500', Color(0xFFF43F5E)), // Default rose-500
    AvatarColorOption('bg-red-600', Color(0xFFDC2626)),
    AvatarColorOption('bg-orange-600', Color(0xFFEA580C)),
    AvatarColorOption('bg-amber-600', Color(0xFFD97706)),
    AvatarColorOption('bg-yellow-500', Color(0xFFEAB308)),
    AvatarColorOption('bg-lime-500', Color(0xFF84CC16)),
    AvatarColorOption('bg-green-500', Color(0xFF22C55E)),
    AvatarColorOption('bg-emerald-500', Color(0xFF10B981)),
    AvatarColorOption('bg-teal-500', Color(0xFF14B8A6)),
    AvatarColorOption('bg-cyan-500', Color(0xFF06B6D4)),
    AvatarColorOption('bg-sky-500', Color(0xFF0EA5E9)),
    AvatarColorOption('bg-blue-600', Color(0xFF2563EB)),
    AvatarColorOption('bg-indigo-600', Color(0xFF4F46E5)),
    AvatarColorOption('bg-violet-600', Color(0xFF7C3AED)),
    AvatarColorOption('bg-purple-600', Color(0xFF9333EA)),
    AvatarColorOption('bg-fuchsia-600', Color(0xFFC026D3)),
    AvatarColorOption('bg-pink-600', Color(0xFFDB2777)),
    AvatarColorOption('bg-rose-600', Color(0xFFE11D48)),
  ];
}

class AvatarColorOption {
  final String tailwindClass;
  final Color color;

  const AvatarColorOption(this.tailwindClass, this.color);
}

/// Text input formatter that capitalizes the first letter of each word
class CapitalizeWordsTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Capitalize first letter of each word
    final words = newValue.text.split(' ');
    final capitalized = words
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');

    return TextEditingValue(text: capitalized, selection: newValue.selection);
  }
}

class BandFormScreen extends ConsumerStatefulWidget {
  final BandFormMode mode;
  final Band? initialBand; // Required for edit mode

  const BandFormScreen({super.key, required this.mode, this.initialBand})
    : assert(
        mode == BandFormMode.create || initialBand != null,
        'initialBand is required for edit mode',
      );

  @override
  ConsumerState<BandFormScreen> createState() => _BandFormScreenState();
}

class _BandFormScreenState extends ConsumerState<BandFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _bandNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _bandNameFocusNode = FocusNode();
  final _bandNameHintController = FieldHintController();

  String _selectedAvatarColor = 'bg-rose-500';
  final List<String> _inviteEmails = [];
  bool _isSubmitting = false;
  bool _isDeleting = false;
  bool _isUploadingImage = false;
  File? _selectedImage;
  String? _uploadedImageUrl;
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedEmailDomain;

  // Initial values for dirty state detection (edit mode)
  String _initialName = '';
  String _initialAvatarColor = 'bg-rose-500';
  String? _initialImageUrl;

  // Edit mode: Members and Invitations
  final _inviteEmailController = TextEditingController();
  List<Map<String, dynamic>> _pendingInvites = [];
  List<Map<String, dynamic>> _members = [];
  bool _isLoadingMembers = false;
  bool _isSendingInvite = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool get _isEditMode => widget.mode == BandFormMode.edit;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();

    // Add listener for live avatar preview when name changes
    _bandNameController.addListener(_onBandNameChanged);

    // Setup field hint controller for band name
    _bandNameFocusNode.addListener(_onBandNameFocusChange);
    _bandNameController.addListener(_onBandNameTextChange);

    // Pre-fill values for edit mode
    if (_isEditMode && widget.initialBand != null) {
      final band = widget.initialBand!;
      _bandNameController.text = band.name;
      _selectedAvatarColor = band.avatarColor;
      _uploadedImageUrl = band.imageUrl;

      // Store initial values for dirty state detection
      _initialName = band.name;
      _initialAvatarColor = band.avatarColor;
      _initialImageUrl = band.imageUrl;

      // Initialize hint as hidden since field has content
      _bandNameHintController.initialize(hasInitialValue: true);

      // Load members and invitations for edit mode
      _loadMembersAndInvites();
    } else {
      // Create mode: no initial value
      _bandNameHintController.initialize(hasInitialValue: false);
    }
  }

  void _onBandNameFocusChange() {
    if (_bandNameFocusNode.hasFocus) {
      _bandNameHintController.onFocus();
    }
  }

  void _onBandNameTextChange() {
    _bandNameHintController.onTextChanged(_bandNameController.text);
  }

  @override
  void dispose() {
    // Remove listener before disposing controller
    _bandNameController.removeListener(_onBandNameChanged);
    _bandNameController.removeListener(_onBandNameTextChange);
    _bandNameFocusNode.removeListener(_onBandNameFocusChange);
    _bandNameController.dispose();
    _emailController.dispose();
    _emailFocusNode.dispose();
    _bandNameFocusNode.dispose();
    _bandNameHintController.dispose();
    _inviteEmailController.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Called when band name text changes - updates local avatar preview only
  /// Header avatar is NOT updated - it only updates after successful save
  void _onBandNameChanged() {
    // Only rebuild if showing generated avatar (no custom image)
    // If user has a local image or network image, don't override the avatar
    final showingGeneratedAvatar =
        _selectedImage == null && _uploadedImageUrl == null;

    if (showingGeneratedAvatar && mounted) {
      final currentName = _bandNameController.text;
      final initials = bandInitials(currentName);
      debugPrint(
        '[BandAvatarPreview] name="$currentName" initials="$initials"',
      );
      setState(() {});
    }
  }

  /// Check if form has changes compared to initial values
  bool get _isDirty {
    if (!_isEditMode) return true; // Create mode is always "dirty"

    final nameChanged = _bandNameController.text.trim() != _initialName;
    final colorChanged = _selectedAvatarColor != _initialAvatarColor;
    final imageChanged =
        _selectedImage != null || _uploadedImageUrl != _initialImageUrl;

    return nameChanged || colorChanged || imageChanged;
  }

  void _addEmail() {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!emailRegex.hasMatch(email)) {
      showErrorSnackBar(context, message: 'Please enter a valid email address');
      return;
    }

    if (_inviteEmails.contains(email)) {
      showAppSnackBar(
        context,
        message: 'Email already added',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    setState(() {
      _inviteEmails.add(email);
      _emailController.clear();
    });
    HapticFeedback.lightImpact();
  }

  void _removeEmail(String email) {
    setState(() {
      _inviteEmails.remove(email);
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    if (_isEditMode) {
      await _updateBand();
    } else {
      await _createBand();
    }
  }

  Future<void> _createBand() async {
    setState(() => _isSubmitting = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to create a band');
      }
      final userId = user.id;
      debugPrint('[CreateBand] User authenticated: $userId');

      final bandName = _bandNameController.text.trim();
      if (bandName.isEmpty) {
        throw Exception('Band name is required');
      }

      // Upload image if selected
      String? imageUrl = _uploadedImageUrl;
      if (_selectedImage != null && imageUrl == null) {
        imageUrl = await _uploadImageToStorage(_selectedImage!);
        if (imageUrl == null && _selectedImage != null) {
          throw StorageException('Image upload failed. Please try again.');
        }
      }

      // Create band via RPC
      final response = await supabase.rpc(
        'create_band',
        params: {
          'p_name': bandName,
          'p_avatar_color': _selectedAvatarColor,
          'p_image_url': imageUrl,
        },
      );

      final String? bandId;
      if (response is String) {
        bandId = response;
      } else if (response != null) {
        bandId = response.toString();
      } else {
        bandId = null;
      }

      if (bandId == null || bandId.isEmpty) {
        throw Exception('Failed to create band - no ID returned');
      }

      // Send invites
      for (final email in _inviteEmails) {
        try {
          // Insert invitation and get the ID
          final insertResponse = await supabase
              .from('band_invitations')
              .insert({
                'band_id': bandId,
                'email': email,
                'invited_by': userId,
                'status': 'pending',
              })
              .select('id')
              .single();

          final inviteId = insertResponse['id'] as String;
          debugPrint('[CreateBand] Created invite id=$inviteId for $email');

          // Call edge function to send email
          try {
            final functionResponse = await supabase.functions.invoke(
              'send-band-invite',
              body: {'bandInvitationId': inviteId},
            );

            if (functionResponse.status == 200) {
              debugPrint('[CreateBand] Invite email sent to $email');
            } else {
              debugPrint(
                '[CreateBand] Invite email failed for $email: ${functionResponse.data}',
              );
              if (mounted) {
                showAppSnackBar(
                  context,
                  message: 'Invite saved but email failed to send',
                  backgroundColor: AppColors.warning,
                );
              }
            }
          } catch (functionError) {
            debugPrint(
              '[CreateBand] Edge function error for $email: $functionError',
            );
            if (mounted) {
              showAppSnackBar(
                context,
                message: 'Invite saved but email failed to send',
                backgroundColor: AppColors.warning,
              );
            }
          }
        } catch (inviteError) {
          debugPrint(
            '[CreateBand] Failed to send invite to $email: $inviteError',
          );
        }
      }

      // Refresh and select new band
      await ref.read(activeBandProvider.notifier).loadAndSelectBand(bandId);

      if (mounted) {
        showSuccessSnackBar(
          context,
          message: '$bandName created successfully!',
        );
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      debugPrint('[CreateBand] PostgrestException: ${e.code} - ${e.message}');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar(_mapPostgrestError(e));
      }
    } on StorageException catch (e) {
      debugPrint('[CreateBand] StorageException: ${e.message}');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar('Image upload failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('[CreateBand] Error: $e');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar('Failed to create band');
      }
    }
  }

  Future<void> _updateBand() async {
    if (!_isDirty) return;

    setState(() => _isSubmitting = true);

    try {
      final band = widget.initialBand!;
      final bandName = _bandNameController.text.trim();

      // Upload new image if selected
      String? imageUrl = _uploadedImageUrl;
      if (_selectedImage != null) {
        final newUrl = await _uploadImageToStorage(_selectedImage!);
        if (newUrl != null) {
          imageUrl = newUrl;
        }
      }

      // Update band in database
      final now = DateTime.now();
      await supabase
          .from('bands')
          .update({
            'name': bandName,
            'avatar_color': _selectedAvatarColor,
            'image_url': imageUrl,
            'updated_at': now.toIso8601String(),
          })
          .eq('id', band.id);

      // Create updated band object and update provider immediately
      // This ensures the header avatar updates without waiting for reload
      final updatedBand = Band(
        id: band.id,
        name: bandName,
        imageUrl: imageUrl,
        createdBy: band.createdBy,
        avatarColor: _selectedAvatarColor,
        createdAt: band.createdAt,
        updatedAt: now,
      );
      ref.read(activeBandProvider.notifier).updateActiveBand(updatedBand);

      if (mounted) {
        showSuccessSnackBar(
          context,
          message: '$bandName updated successfully!',
        );
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      debugPrint('[UpdateBand] PostgrestException: ${e.code} - ${e.message}');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar(_mapPostgrestError(e));
      }
    } catch (e) {
      debugPrint('[UpdateBand] Error: $e');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar('Failed to update band');
      }
    }
  }

  Future<void> _deleteBand() async {
    final band = widget.initialBand;
    if (band == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Band?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${band.name}"? This action cannot be undone and will remove all associated gigs, rehearsals, and member data.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      // Delete band from database
      await supabase.from('bands').delete().eq('id', band.id);

      // Reload bands - this will auto-select another band or show NoBandState
      await ref.read(activeBandProvider.notifier).loadUserBands();

      if (mounted) {
        showSuccessSnackBar(context, message: '${band.name} deleted');
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      debugPrint('[DeleteBand] PostgrestException: ${e.code} - ${e.message}');
      setState(() => _isDeleting = false);
      if (mounted) {
        _showErrorSnackBar('Failed to delete band: ${e.message}');
      }
    } catch (e) {
      debugPrint('[DeleteBand] Error: $e');
      setState(() => _isDeleting = false);
      if (mounted) {
        _showErrorSnackBar('Failed to delete band');
      }
    }
  }

  // ===========================================================================
  // EDIT MODE: Members and Invitations
  // ===========================================================================

  Future<void> _loadMembersAndInvites() async {
    if (!_isEditMode || widget.initialBand == null) return;

    setState(() => _isLoadingMembers = true);

    try {
      final bandId = widget.initialBand!.id;

      // 1. Load band members (NO embedded join - just band_members table)
      // Include both 'active' and 'invited' statuses
      final membersResponse = await supabase
          .from('band_members')
          .select('id, user_id, role, status, joined_at')
          .eq('band_id', bandId)
          .inFilter('status', ['active', 'invited']);

      final membersList = List<Map<String, dynamic>>.from(membersResponse);

      // 2. Fetch user info for all members (separate query)
      final userIds = membersList
          .map((m) => m['user_id'] as String?)
          .whereType<String>()
          .toList();

      Map<String, Map<String, dynamic>> usersById = {};
      if (userIds.isNotEmpty) {
        final usersResponse = await supabase
            .from('users')
            .select('id, email, first_name, last_name')
            .inFilter('id', userIds);

        for (final user in usersResponse) {
          usersById[user['id'] as String] = user;
        }
      }

      // 3. Merge user data into members and collect emails
      final Set<String> memberEmailSet = {};
      for (final member in membersList) {
        final userId = member['user_id'] as String?;
        if (userId != null && usersById.containsKey(userId)) {
          member['user_info'] = usersById[userId];
          final email = usersById[userId]?['email'] as String?;
          if (email != null) {
            memberEmailSet.add(email.toLowerCase());
          }
        }
      }

      // 4. Load pending invitations (both 'pending' and 'sent' statuses)
      final invitesResponse = await supabase
          .from('band_invitations')
          .select('id, email, status, created_at')
          .eq('band_id', bandId)
          .inFilter('status', ['pending', 'sent'])
          .order('created_at', ascending: false);

      final invitesList = List<Map<String, dynamic>>.from(invitesResponse);

      // 5. Filter out invites where email matches an active member
      final filteredInvites = invitesList.where((invite) {
        final email = (invite['email'] as String?)?.toLowerCase().trim() ?? '';
        return !memberEmailSet.contains(email);
      }).toList();

      // 6. Dedupe invites by email (keep newest created_at)
      final Map<String, Map<String, dynamic>> dedupedByEmail = {};
      for (final invite in filteredInvites) {
        final email = (invite['email'] as String?)?.toLowerCase().trim() ?? '';
        if (!dedupedByEmail.containsKey(email)) {
          dedupedByEmail[email] = invite;
        }
        // Already sorted by created_at desc, so first one is newest
      }
      final dedupedInvites = dedupedByEmail.values.toList();

      if (mounted) {
        setState(() {
          _members = membersList;
          _pendingInvites = dedupedInvites;
          _isLoadingMembers = false;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint(
        '[LoadMembersAndInvites] PostgrestException: ${e.code} - ${e.message}',
      );
      if (mounted) {
        setState(() => _isLoadingMembers = false);
        _showErrorSnackBar('Failed to load members');
      }
    } catch (e) {
      debugPrint('[LoadMembersAndInvites] Error: $e');
      if (mounted) {
        setState(() => _isLoadingMembers = false);
        _showErrorSnackBar('Failed to load members');
      }
    }
  }

  Future<void> _sendInvite() async {
    final email = _inviteEmailController.text.trim().toLowerCase();
    if (email.isEmpty || widget.initialBand == null) return;

    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!emailRegex.hasMatch(email)) {
      _showErrorSnackBar('Please enter a valid email address');
      return;
    }

    // Check if already a member
    final memberEmails = _members
        .map((m) => (m['user_info']?['email'] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();
    if (memberEmails.contains(email)) {
      _showErrorSnackBar('This person is already a band member');
      return;
    }

    // Check if inviting yourself
    final user = supabase.auth.currentUser;
    if (user?.email?.toLowerCase() == email) {
      _showErrorSnackBar('You cannot invite yourself');
      return;
    }

    final bandId = widget.initialBand!.id;

    // Check for existing pending invite in the database (not just local state)
    try {
      final existingInvites = await supabase
          .from('band_invitations')
          .select('id')
          .eq('band_id', bandId)
          .eq('email', email)
          .inFilter('status', ['pending', 'sent']);

      if (existingInvites.isNotEmpty) {
        _showErrorSnackBar('User already invited');
        return;
      }
    } catch (e) {
      debugPrint('[Invite] Failed to check existing invites: $e');
    }

    setState(() => _isSendingInvite = true);

    try {
      final userId = supabase.auth.currentUser?.id;

      // Insert invitation and get the returned row
      final insertResponse = await supabase
          .from('band_invitations')
          .insert({
            'band_id': bandId,
            'email': email,
            'invited_by': userId,
            'status': 'pending',
          })
          .select('id, token')
          .single();

      final inviteId = insertResponse['id'] as String;
      debugPrint('[Invite] inserted invitation id=$inviteId email=$email');

      _inviteEmailController.clear();

      // Call edge function to send email via Resend
      debugPrint('[Invite] invoking send-band-invite id=$inviteId');

      try {
        final functionResponse = await supabase.functions.invoke(
          'send-band-invite',
          body: {'bandInvitationId': inviteId},
        );

        if (functionResponse.status == 200) {
          debugPrint('[Invite] send success id=$inviteId');
          if (mounted) {
            showSuccessSnackBar(context, message: 'Invite sent to $email');
          }
        } else {
          final errorData = functionResponse.data;
          debugPrint('[Invite] send failed id=$inviteId error=$errorData');
          if (mounted) {
            showAppSnackBar(
              context,
              message: 'Invite saved but email failed to send',
              backgroundColor: AppColors.warning,
            );
          }
        }
      } catch (functionError) {
        debugPrint('[Invite] send failed id=$inviteId error=$functionError');
        if (mounted) {
          showAppSnackBar(
            context,
            message: 'Invite saved but email failed to send',
            backgroundColor: AppColors.warning,
          );
        }
      }

      await _loadMembersAndInvites();
    } on PostgrestException catch (e) {
      debugPrint('[SendInvite] PostgrestException: ${e.code} - ${e.message}');
      if (e.code == '23505') {
        _showErrorSnackBar('User already invited');
      } else if (e.code == '42501') {
        // RLS policy violation - user is not a band admin
        _showErrorSnackBar('Only band admins can invite members');
      } else {
        _showErrorSnackBar('Failed to send invitation');
      }
    } catch (e) {
      debugPrint('[SendInvite] Error: $e');
      _showErrorSnackBar('Failed to send invitation');
    } finally {
      if (mounted) {
        setState(() => _isSendingInvite = false);
      }
    }
  }

  Future<void> _cancelInvite(Map<String, dynamic> invite) async {
    if (widget.initialBand == null) return;

    final email = invite['email'] ?? '';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Invite?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Cancel invite for $email?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Cancel Invite',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final bandId = widget.initialBand!.id;

      // Hard delete the invitation row (cancellations are usually typos)
      await supabase
          .from('band_invitations')
          .delete()
          .eq('id', invite['id'])
          .eq('band_id', bandId);

      debugPrint('[CancelInvite] deleted invite ${invite['id']} for $email');

      await _loadMembersAndInvites();

      if (mounted) {
        showSuccessSnackBar(context, message: 'Invitation to $email removed');
      }
    } on PostgrestException catch (e) {
      debugPrint('[CancelInvite] PostgrestException: ${e.code} - ${e.message}');
      if (mounted) {
        _showErrorSnackBar('Failed to cancel invite');
      }
    } catch (e) {
      debugPrint('[CancelInvite] Error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to cancel invite');
      }
    }
  }

  /// Get display name for a member from user_info
  String _getMemberDisplayName(Map<String, dynamic> member) {
    final userInfo = member['user_info'] as Map<String, dynamic>?;
    if (userInfo != null) {
      final firstName = userInfo['first_name'] as String? ?? '';
      final lastName = userInfo['last_name'] as String? ?? '';
      if (firstName.isNotEmpty || lastName.isNotEmpty) {
        return '$firstName $lastName'.trim();
      }
      final email = userInfo['email'] as String?;
      if (email != null && email.isNotEmpty) {
        return email;
      }
    }
    // Fallback to short ID
    final id = member['id'] as String? ?? '';
    return 'Member ${id.substring(0, 6)}';
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final user = supabase.auth.currentUser;
    if (user == null || widget.initialBand == null) return;

    // Prevent removing yourself
    if (member['user_id'] == user.id) {
      _showErrorSnackBar('You cannot remove yourself from the band');
      return;
    }

    final displayName = _getMemberDisplayName(member);

    // Show confirmation dialog (action button first, then Cancel)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Member?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove $displayName from this band?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Remove',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final bandId = widget.initialBand!.id;

      // Hard delete the band membership row (NOT the user - they remain in public.users)
      try {
        await supabase
            .from('band_members')
            .delete()
            .eq('id', member['id'])
            .eq('band_id', bandId);
      } catch (deleteError) {
        // Fallback to soft delete if RLS/permissions prevent hard delete
        debugPrint(
          '[RemoveMember] Hard delete failed, falling back to soft delete: $deleteError',
        );
        await supabase
            .from('band_members')
            .update({'status': 'removed'})
            .eq('id', member['id'])
            .eq('band_id', bandId);
      }

      debugPrint(
        '[RemoveMember] removed membership ${member['id']} for $displayName',
      );

      await _loadMembersAndInvites();

      if (mounted) {
        showSuccessSnackBar(context, message: '$displayName removed from band');
      }
    } on PostgrestException catch (e) {
      debugPrint('[RemoveMember] PostgrestException: ${e.code} - ${e.message}');
      if (mounted) {
        _showErrorSnackBar('Failed to remove member');
      }
    } catch (e) {
      debugPrint('[RemoveMember] Error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to remove member');
      }
    }
  }

  String _mapPostgrestError(PostgrestException e) {
    if (e.code == '42883' ||
        (e.message.contains('function') &&
            e.message.contains('does not exist'))) {
      return 'Server configuration error. Please contact support.';
    } else if (e.code == '42501' || e.message.contains('permission denied')) {
      return 'Permission denied. Please sign out and back in.';
    } else if (e.message.contains('Authentication required')) {
      return 'Please sign in to continue';
    }
    return 'An error occurred. Please try again.';
  }

  void _showErrorSnackBar(String message) {
    showErrorSnackBar(context, message: message);
  }

  Future<String?> _uploadImageToStorage(File imageFile) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName = '$userId/$timestamp.$extension';

      final bytes = await imageFile.readAsBytes();

      await supabase.storage
          .from('band-avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );

      return supabase.storage.from('band-avatars').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Failed to upload image: $e');
      return null;
    }
  }

  /// Check and request camera permission
  /// Returns true if permission is granted, false otherwise
  Future<bool> _checkCameraPermission() async {
    // Check if running on web - permissions work differently
    if (Platform.isIOS || Platform.isAndroid) {
      final status = await Permission.camera.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isDenied) {
        // Request permission
        final result = await Permission.camera.request();
        if (result.isGranted) {
          return true;
        }
      }

      // Permission is permanently denied or restricted
      if (status.isPermanentlyDenied || status.isRestricted) {
        if (mounted) {
          await _showPermissionDeniedDialog(
            title: 'Camera Access Required',
            message:
                'BandRoadie needs camera access to take photos. Please enable camera access in Settings.',
          );
        }
        return false;
      }

      // Permission was denied after request
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Camera permission is required to take photos',
          backgroundColor: AppColors.warning,
        );
      }
      return false;
    }

    // For other platforms (macOS, web), assume permission is granted
    return true;
  }

  /// Check and request photo library permission
  /// Returns true if permission is granted, false otherwise
  Future<bool> _checkPhotoLibraryPermission() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final status = await Permission.photos.status;

      if (status.isGranted || status.isLimited) {
        return true;
      }

      if (status.isDenied) {
        final result = await Permission.photos.request();
        if (result.isGranted || result.isLimited) {
          return true;
        }
      }

      if (status.isPermanentlyDenied || status.isRestricted) {
        if (mounted) {
          await _showPermissionDeniedDialog(
            title: 'Photo Library Access Required',
            message:
                'BandRoadie needs access to your photo library to select images. Please enable access in Settings.',
          );
        }
        return false;
      }

      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Photo library permission is required',
          backgroundColor: AppColors.warning,
        );
      }
      return false;
    }

    return true;
  }

  /// Show a dialog explaining that permission was denied and how to enable it
  Future<void> _showPermissionDeniedDialog({
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Spacing.space16),
              const Text(
                'Choose Image Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.space24),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: AppColors.accent,
                  ),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Use camera to take a new photo',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: Spacing.space8),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: AppColors.accent,
                  ),
                ),
                title: const Text(
                  'Photo Library',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Choose from your photos',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: Spacing.space16),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    // Check permissions before accessing camera/gallery
    bool hasPermission = false;
    if (source == ImageSource.camera) {
      hasPermission = await _checkCameraPermission();
    } else {
      hasPermission = await _checkPhotoLibraryPermission();
    }

    if (!hasPermission) {
      debugPrint('[PickImage] Permission denied for ${source.name}');
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) {
        // User cancelled - this is normal, not an error
        debugPrint('[PickImage] User cancelled image selection');
        return;
      }

      final imageFile = File(image.path);
      setState(() {
        _selectedImage = imageFile;
        _isUploadingImage = true;
        _uploadedImageUrl = null;
      });
      HapticFeedback.lightImpact();

      // Upload immediately for better UX
      final uploadedUrl = await _uploadImageToStorage(imageFile);

      if (mounted) {
        setState(() {
          _uploadedImageUrl = uploadedUrl;
          _isUploadingImage = false;
        });

        if (uploadedUrl != null) {
          showSuccessSnackBar(context, message: 'Image uploaded successfully');
        }
      }
    } on PlatformException catch (e) {
      // Handle platform-specific errors (e.g., camera not available)
      debugPrint('[PickImage] PlatformException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() => _isUploadingImage = false);
        if (e.code == 'camera_access_denied') {
          await _showPermissionDeniedDialog(
            title: 'Camera Access Required',
            message: 'Please enable camera access in Settings to take photos.',
          );
        } else if (e.code == 'photo_access_denied') {
          await _showPermissionDeniedDialog(
            title: 'Photo Library Access Required',
            message: 'Please enable photo library access in Settings.',
          );
        } else {
          showErrorSnackBar(
            context,
            message: 'Unable to access camera. Please try again.',
          );
        }
      }
    } catch (e) {
      debugPrint('[PickImage] Error: $e');
      if (mounted) {
        setState(() => _isUploadingImage = false);
        showErrorSnackBar(
          context,
          message: 'Failed to pick image. Please try again.',
        );
      }
    }
  }

  void _addEmailDomain(String domain) {
    final currentText = _emailController.text.trim();
    if (currentText.isEmpty) {
      showAppSnackBar(
        context,
        message: 'Please enter a username first',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    String newEmail;
    if (currentText.contains('@')) {
      final username = currentText.split('@').first;
      newEmail = '$username$domain';
    } else {
      newEmail = '$currentText$domain';
    }

    setState(() {
      _emailController.text = newEmail;
      _selectedEmailDomain = domain;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditMode ? 'Edit Band' : 'Create New Band';
    final subtitle = _isEditMode
        ? 'Update your band details'
        : 'Set up your band and invite members';
    final submitLabel = _isEditMode ? 'Update Band' : 'Create Band';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(Spacing.pagePadding),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: Spacing.space32),

                              // Band name input
                              _buildSectionLabel('Band name'),
                              const SizedBox(height: Spacing.space8),
                              _buildTextInput(
                                controller: _bandNameController,
                                focusNode: _bandNameFocusNode,
                                hintText: 'Enter band name',
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  CapitalizeWordsTextFormatter(),
                                ],
                                // Note: Live avatar preview handled by _onBandNameChanged listener
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a band name';
                                  }
                                  return null;
                                },
                              ),
                              FieldHint(
                                text:
                                    "This is how your band will appear everywhere.",
                                controller: _bandNameHintController,
                              ),
                              const SizedBox(height: Spacing.space24),

                              // Band avatar section
                              _buildSectionLabel('Band avatar'),
                              const SizedBox(height: Spacing.space12),
                              _buildAvatarSection(),
                              const SizedBox(height: Spacing.space32),

                              // Edit mode: Invite Members section
                              if (_isEditMode) ...[
                                _buildSectionLabel('Invite Members'),
                                const SizedBox(height: Spacing.space6),
                                const Text(
                                  'Send an invitation to join your band',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: Spacing.space12),
                                _buildInviteEmailInput(),

                                // Invited section (only if there are pending invites)
                                if (_pendingInvites.isNotEmpty) ...[
                                  const SizedBox(height: Spacing.space24),
                                  _buildSectionLabel('Invited'),
                                  const SizedBox(height: Spacing.space12),
                                  _buildPendingInvitesList(),
                                ],

                                // Members section
                                const SizedBox(height: Spacing.space32),
                                _buildSectionLabel('Members'),
                                const SizedBox(height: Spacing.space12),
                                _buildMembersSection(),
                                const SizedBox(height: Spacing.space32),
                              ],

                              // Invite members section (only for create mode)
                              if (!_isEditMode) ...[
                                _buildSectionLabel('Invite Members'),
                                const SizedBox(height: Spacing.space6),
                                const Text(
                                  'Add email addresses to invite members to your band',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: Spacing.space12),
                                _buildEmailInput(),
                                const SizedBox(height: Spacing.space8),
                                _buildEmailDomainShortcuts(),

                                if (_inviteEmails.isNotEmpty) ...[
                                  const SizedBox(height: Spacing.space24),
                                  _buildSectionLabel('Invites sent'),
                                  const SizedBox(height: Spacing.space12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _inviteEmails
                                        .map(
                                          (email) => _EmailPill(
                                            email: email,
                                            onRemove: () => _removeEmail(email),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],

                              // Submit button
                              const SizedBox(height: Spacing.space32),
                              _buildSubmitButton(submitLabel),
                              const SizedBox(height: Spacing.space48),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return FrostedGlassBar(
      height: Spacing.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.textPrimary,
                  size: 24,
                ),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String hintText,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
        ),
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.space16,
          vertical: Spacing.space14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    // Track if we have a network image (uploaded but not locally selected)
    final hasNetworkImage = _uploadedImageUrl != null && _selectedImage == null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar preview - uses same BandAvatar widget as header for consistency
        Stack(
          children: [
            BandAvatar(
              imageUrl: _selectedImage == null ? _uploadedImageUrl : null,
              localImageFile: _selectedImage,
              name: _bandNameController.text.trim().isEmpty
                  ? null
                  : _bandNameController.text.trim(),
              avatarColor: _selectedAvatarColor,
              size: 75,
              fontSize: 28,
            ),
            if (_isUploadingImage)
              Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            if (_uploadedImageUrl != null && !_isUploadingImage)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.scaffoldBg, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: AvatarColors.colors.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceDark,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.borderMuted,
                                width: 1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.upload_rounded,
                                color: AppColors.textPrimary,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final colorIndex = index - 1;
                    final colorOption = AvatarColors.colors[colorIndex];
                    final isSelected =
                        colorOption.tailwindClass == _selectedAvatarColor &&
                        _selectedImage == null &&
                        !hasNetworkImage;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: colorIndex < AvatarColors.colors.length - 1
                            ? 8
                            : 0,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarColor = colorOption.tailwindClass;
                            _selectedImage = null;
                            _uploadedImageUrl = null;
                          });
                          HapticFeedback.selectionClick();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: colorOption.color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: colorOption.color.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: Spacing.space8),
              const Text(
                'Upload an image or choose a color for your band avatar.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _addEmail(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.surfaceDark,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.space12),
        GestureDetector(
          onTap: _addEmail,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            ),
            child: const Center(
              child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailDomainShortcuts() {
    const domains = ['@gmail.com', '@yahoo.com', '@icloud.com', '@outlook.com'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: domains.asMap().entries.map((entry) {
          final index = entry.key;
          final domain = entry.value;
          final isSelected = _selectedEmailDomain == domain;
          return Padding(
            padding: EdgeInsets.only(right: index < domains.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                setState(
                  () => _selectedEmailDomain = isSelected ? null : domain,
                );
                _addEmailDomain(domain);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.space8,
                  vertical: Spacing.space8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.transparent
                      : const Color(0xFF444444),
                  borderRadius: BorderRadius.circular(50),
                  border: isSelected
                      ? Border.all(color: AppColors.accent, width: 1)
                      : null,
                ),
                child: Text(
                  domain,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.33,
                    color: isSelected
                        ? AppColors.accent
                        : const Color(0xFFF5F5F5),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // Edit Mode: Invite Members + Members UI
  // ===========================================================================

  Widget _buildInviteEmailInput() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _inviteEmailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _sendInvite(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.surfaceDark,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.space12),
        GestureDetector(
          onTap: _isSendingInvite ? null : _sendInvite,
          child: Container(
            width: 80,
            height: 48,
            decoration: BoxDecoration(
              color: _isSendingInvite
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : AppColors.accent,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            ),
            child: Center(
              child: _isSendingInvite
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Invite',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingInvitesList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _pendingInvites.map((invite) {
        return _InvitePill(
          email: invite['email'] ?? '',
          onCancel: () => _cancelInvite(invite),
        );
      }).toList(),
    );
  }

  Widget _buildMembersSection() {
    if (_isLoadingMembers) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.space16),
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_members.isEmpty) {
      return const Text(
        'No members yet. Invite people to join your band!',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      );
    }

    final currentUserId = supabase.auth.currentUser?.id;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _members.map((member) {
        final isCurrentUser = member['user_id'] == currentUserId;
        final displayName = _getMemberDisplayName(member);

        return _MemberChip(
          displayName: displayName,
          isCurrentUser: isCurrentUser,
          onRemove: isCurrentUser ? null : () => _removeMember(member),
        );
      }).toList(),
    );
  }

  Widget _buildSubmitButton(String label) {
    final isEnabled = _isEditMode
        ? _isDirty && !_isSubmitting && !_isDeleting
        : !_isSubmitting;

    return Column(
      children: [
        BrandActionButton(
          label: label,
          fullWidth: true,
          height: 52,
          isLoading: _isSubmitting,
          onPressed: isEnabled ? _submitForm : null,
        ),
        const SizedBox(height: Spacing.space16),
        // Cancel button
        TextButton(
          onPressed: (_isSubmitting || _isDeleting)
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        // Delete button (edit mode only)
        if (_isEditMode) ...[
          const SizedBox(height: Spacing.space8),
          TextButton(
            onPressed: (_isSubmitting || _isDeleting) ? null : _deleteBand,
            child: _isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.accent,
                      ),
                    ),
                  )
                : const Text(
                    'Delete',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.accent,
                      decoration: TextDecoration.none,
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// EMAIL PILL WIDGET
// ============================================================================

class _EmailPill extends StatelessWidget {
  final String email;
  final VoidCallback onRemove;

  const _EmailPill({required this.email, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: Spacing.space8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF444444),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            email,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.33,
              color: Color(0xFFF5F5F5),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFFF5F5F5),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// INVITE PILL WIDGET (for pending invitations)
// ============================================================================

class _InvitePill extends StatelessWidget {
  final String email;
  final VoidCallback onCancel;

  const _InvitePill({required this.email, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF444444),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 14,
              color: AppColors.warning,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                email.trim(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                  color: Color(0xFFF5F5F5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCancel,
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFFF5F5F5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MEMBER CHIP WIDGET
// ============================================================================

class _MemberChip extends StatelessWidget {
  final String displayName;
  final bool isCurrentUser;
  final VoidCallback? onRemove;

  const _MemberChip({
    required this.displayName,
    required this.isCurrentUser,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF444444),
          borderRadius: BorderRadius.circular(50),
          border: isCurrentUser
              ? Border.all(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName.trim(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                  color: Color(0xFFF5F5F5),
                ),
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 6),
              const Text(
                '(you)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFFF5F5F5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
