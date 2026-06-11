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
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/brand_action_button.dart';
import '../../components/ui/email_domain_shortcut_bar.dart';
import '../../components/ui/field_hint.dart';
import '../../components/ui/frosted_glass_bar.dart';
import '../../shared/utils/initials.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../members/permissions/band_permissions_provider.dart';
import 'active_band_controller.dart';
import 'widgets/band_avatar.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../settings/data_backup_service.dart';
import '../gigs/gig_controller.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../setlists/setlists_screen.dart';
import 'band_full_state.dart';

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
    final capitalized = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

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
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isUploadingImage = false;
  File? _selectedImage;
  String? _uploadedImageUrl;
  final ImagePicker _imagePicker = ImagePicker();

  // Initial values for dirty state detection (edit mode)
  String _initialName = '';
  String _initialAvatarColor = 'bg-rose-500';
  String? _initialImageUrl;
  String _initialTimezone = 'America/Chicago';
  String _selectedTimezone = 'America/Chicago';

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
      _initialTimezone = band.timezone;
      _selectedTimezone = band.timezone;

      // Initialize draft band state for real-time header preview
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(draftBandProvider.notifier).startEditing(band);
      });

      // Initialize hint as hidden since field has content
      _bandNameHintController.initialize(hasInitialValue: true);
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
    // Clear draft state if user navigates away without saving
    if (_isEditMode) {
      // Use addPostFrameCallback to avoid modifying provider during dispose
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(draftBandProvider.notifier).cancelEditing();
      });
    }
    // Remove listener before disposing controller
    _bandNameController.removeListener(_onBandNameChanged);
    _bandNameController.removeListener(_onBandNameTextChange);
    _bandNameFocusNode.removeListener(_onBandNameFocusChange);
    _bandNameController.dispose();
    _emailController.dispose();
    _emailFocusNode.dispose();
    _bandNameFocusNode.dispose();
    _bandNameHintController.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Called when band name text changes - updates both local and header avatar preview
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

      // Update draft state for header avatar preview in edit mode
      if (_isEditMode) {
        ref.read(draftBandProvider.notifier).updateName(currentName);
      }
    }
  }

  /// Check if form has changes compared to initial values
  bool get _isDirty {
    if (!_isEditMode) return true; // Create mode is always "dirty"

    final nameChanged = _bandNameController.text.trim() != _initialName;
    final colorChanged = _selectedAvatarColor != _initialAvatarColor;
    final imageChanged =
        _selectedImage != null || _uploadedImageUrl != _initialImageUrl;
    final timezoneChanged = _selectedTimezone != _initialTimezone;

    return nameChanged || colorChanged || imageChanged || timezoneChanged;
  }

  void _addEmail() {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );
    if (!emailRegex.hasMatch(email)) {
      showErrorSnackBar(context, message: 'Please enter a valid email address');
      return;
    }

    if (_inviteEmails.contains(email)) {
      showAppSnackBar(
        context,
        message: 'Email already added',
        backgroundColor: context.colors.warning,
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

      // Save selected timezone
      if (_selectedTimezone != 'America/Chicago') {
        await supabase
            .from('bands')
            .update({'timezone': _selectedTimezone}).eq('id', bandId);
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
                  backgroundColor: context.colors.warning,
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
                backgroundColor: context.colors.warning,
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
    } on PostgrestException catch (e, stack) {
      debugPrint('[CreateBand] PostgrestException: ${e.code} - ${e.message}');
      debugPrint('[CreateBand] Details: ${e.details}');
      debugPrint('[CreateBand] Hint: ${e.hint}');
      debugPrint('[CreateBand] Stack: $stack');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar(_mapPostgrestError(e));
      }
    } on StorageException catch (e, stack) {
      debugPrint('[CreateBand] StorageException: ${e.message}');
      debugPrint('[CreateBand] Stack: $stack');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar('Image upload failed: ${e.message}');
      }
    } catch (e, stack) {
      debugPrint('[CreateBand] Error: $e');
      debugPrint('[CreateBand] Error type: ${e.runtimeType}');
      debugPrint('[CreateBand] Stack: $stack');
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showErrorSnackBar(
          'Failed to create band: ${e.toString().length > 200 ? e.toString().substring(0, 200) : e.toString()}',
        );
      }
    }
  }

  Future<void> _updateBand() async {
    if (!_isDirty) return;

    setState(() => _isSubmitting = true);

    try {
      final band = widget.initialBand!;
      final bandName = _bandNameController.text.trim();

      // Upload new image if selected and not already uploaded
      String? imageUrl = _uploadedImageUrl;
      if (_selectedImage != null && imageUrl == null) {
        final newUrl = await _uploadImageToStorage(_selectedImage!);
        if (newUrl != null) {
          imageUrl = newUrl;
        } else {
          // Upload failed and we don't have a URL - show error
          debugPrint('[UpdateBand] Image upload failed');
          if (mounted) {
            setState(() => _isSubmitting = false);
            showErrorSnackBar(context, message: 'Failed to upload image');
          }
          return;
        }
      }

      // Update band in database
      final now = DateTime.now();
      await supabase.from('bands').update({
        'name': bandName,
        'avatar_color': _selectedAvatarColor,
        'image_url': imageUrl,
        'timezone': _selectedTimezone,
        'updated_at': now.toIso8601String(),
      }).eq('id', band.id);

      // Create updated band object and update provider immediately
      // This ensures the header avatar updates without waiting for reload
      final updatedBand = Band(
        id: band.id,
        name: bandName,
        imageUrl: imageUrl,
        createdBy: band.createdBy,
        avatarColor: _selectedAvatarColor,
        timezone: _selectedTimezone,
        createdAt: band.createdAt,
        updatedAt: now,
      );
      ref.read(activeBandProvider.notifier).updateActiveBand(updatedBand);

      // Clear draft state since changes are now saved
      ref.read(draftBandProvider.notifier).finishEditing();

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

  // ─────────────────────────────────────────────────────────────────────────
  // BACKUP / RESTORE
  // ─────────────────────────────────────────────────────────────────────────

  void _showBackupRestoreSheet() {
    final permissionsAsync = ref.read(currentUserPermissionsProvider);
    final canRestore = permissionsAsync.when(
      data: (perms) => perms.canDeleteBand,
      loading: () => false,
      error: (_, __) => false,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: context.colors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (canRestore)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _BackupSheetPanel(
                            icon: AppIcons.download,
                            label: 'Backup Data',
                            description:
                                'Save a local copy of your band\'s current data.',
                            bullets: const [
                              'Band info & members',
                              'Songs & setlists',
                              'Gigs & rehearsals',
                              'Block-out dates',
                            ],
                            isLoading: _isExporting,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _startExport();
                            },
                          ),
                        ),
                        VerticalDivider(
                          width: 28,
                          thickness: 1,
                          color:
                              context.colors.textMuted.withValues(alpha: 0.2),
                        ),
                        Expanded(
                          child: _BackupSheetPanel(
                            icon: AppIcons.rotateCcw,
                            label: 'Restore Data',
                            description:
                                'Replace current band data with a backup file.',
                            bullets: const [
                              'Band info & members',
                              'Songs & setlists',
                              'Gigs & rehearsals',
                              'Block-out dates',
                            ],
                            isLoading: _isImporting,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _showImportDialog();
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _BackupSheetPanel(
                    icon: AppIcons.download,
                    label: 'Backup Data',
                    description:
                        'Save a local copy of your band\'s current data.',
                    bullets: const [
                      'Band info & members',
                      'Songs & setlists',
                      'Gigs & rehearsals',
                      'Block-out dates',
                    ],
                    isLoading: _isExporting,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startExport();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Directly opens the file-save picker with no intermediate dialog.
  Future<void> _startExport() async {
    final band = widget.initialBand;
    if (band == null) return;
    await _performExport(band.id, band.name);
  }

  // ignore: unused_element
  Future<void> _showExportDialog() async {
    final band = widget.initialBand;
    if (band == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(AppIcons.download, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Backup Band Data',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A backup file will be created for ${band.name}. The backup includes:',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...[
              'Band details and settings',
              'Members and roles',
              'Songs and setlists',
              'Gigs and rehearsals',
              'Block-out dates',
            ].map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 14)),
                    Expanded(
                        child: Text(item,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 14))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠ Backup files may contain sensitive information such as lyrics, notes, and member details. Store the file securely.',
                style: TextStyle(color: context.colors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Backup',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _performExport(band.id, band.name);
    }
  }

  Future<void> _performExport(String bandId, String bandName) async {
    setState(() => _isExporting = true);
    try {
      await DataBackupService.exportBandData(bandId, bandName);
      if (mounted) {
        showSuccessSnackBar(context, message: 'Backup created successfully');
      }
    } on DataBackupCancelledException {
      // User dismissed the dialog — no message needed
    } on DataBackupException catch (e) {
      if (mounted) _showErrorSnackBar(e.message);
    } catch (e) {
      debugPrint('[Backup] Export error: $e');
      if (mounted) _showErrorSnackBar('Backup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _showImportDialog() async {
    final band = widget.initialBand;
    if (band == null) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (_) {
      if (mounted) _showErrorSnackBar('Could not open file picker.');
      return;
    }

    if (result == null || result.files.single.bytes == null) return;

    final String jsonContent;
    try {
      jsonContent = utf8.decode(result.files.single.bytes!);
    } catch (_) {
      if (mounted) _showErrorSnackBar('Could not read the selected file.');
      return;
    }

    final BandBackupStats stats;
    try {
      stats = DataBackupService.previewBackup(jsonContent);
    } on DataBackupException catch (e) {
      if (mounted) _showErrorSnackBar(e.message);
      return;
    } catch (_) {
      if (mounted) {
        _showErrorSnackBar('This file does not appear to be a valid backup.');
      }
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(AppIcons.warning, color: context.colors.warning, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Restore Band Data?',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 15),
                children: [
                  const TextSpan(
                      text:
                          'Your current data will be replaced with the backup from '),
                  TextSpan(
                      text: stats.bandName,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const TextSpan(text: '. The following will be replaced:'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildRestoreRow('Members', stats.memberCount),
            _buildRestoreRow('Songs', stats.songCount),
            _buildRestoreRow('Setlists', stats.setlistCount),
            _buildRestoreRow('Gigs', stats.gigCount),
            _buildRestoreRow('Rehearsals', stats.rehearsalCount),
            _buildRestoreRow('Block-out dates', stats.blockOutCount),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'This cannot be undone. Make sure you have a current backup before restoring.',
                style: TextStyle(
                    color: AppColors.error,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Replace Data',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _performImport(jsonContent, band.id);
    }
  }

  Widget _buildRestoreRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('• ',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 15)),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 15))),
          Text('$count',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _performImport(String jsonContent, String bandId) async {
    setState(() => _isImporting = true);
    try {
      await DataBackupService.importBandData(jsonContent, bandId);
      // Force all band-data providers to re-fetch from Supabase immediately.
      // Use .refresh() / invalidate rather than .invalidate() alone, because
      // the notifiers derive from bandFullStateProvider (RPC cache) and would
      // otherwise re-read stale cached data.
      // Refresh each provider directly from Supabase. Do NOT also invalidate
      // bandFullStateProvider at the same time — concurrent RPC + direct fetches
      // race and can freeze/crash the dashboard.
      await Future.wait([
        ref.read(gigProvider.notifier).refresh(),
        ref.read(rehearsalProvider.notifier).refresh(),
        ref.read(setlistsProvider.notifier).refresh(),
      ]);
      // Invalidate the RPC cache afterwards so the next full load is fresh.
      ref.invalidate(bandFullStateProvider);
      if (mounted) {
        showSuccessSnackBar(context, message: 'Data restored successfully');
      }
    } on DataBackupException catch (e) {
      if (mounted) _showErrorSnackBar(e.message);
    } catch (e) {
      debugPrint('[Restore] Unexpected error: $e');
      if (mounted) {
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        _showErrorSnackBar('Restore failed: $msg');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _deleteBand() async {
    final band = widget.initialBand;
    if (band == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Band?',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${band.name}"? This action cannot be undone and will remove all associated gigs, rehearsals, and member data.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      // Delete band using RPC function (bypasses RLS with proper auth checks)
      // Returns true on success, throws exception on failure
      final result = await supabase.rpc(
        'delete_band',
        params: {'band_uuid': band.id},
      );

      debugPrint('[DeleteBand] RPC result: $result');

      // Verify the deletion actually succeeded
      if (result != true) {
        debugPrint(
          '[DeleteBand] RPC returned false or null, deletion may have failed',
        );
        setState(() => _isDeleting = false);
        if (mounted) {
          _showErrorSnackBar(
            'Failed to delete band: operation did not complete',
          );
        }
        return;
      }

      // Store band ID before cleanup (for debug logging)
      final deletedBandId = band.id;
      final bandName = band.name;

      // Clear the draft band state if we were editing
      ref.read(draftBandProvider.notifier).cancelEditing();

      // Handle band deletion cleanup: clears persisted ID, reloads bands,
      // selects new active band, and navigates to Dashboard
      await ref
          .read(activeBandProvider.notifier)
          .handleBandDeletion(deletedBandId);

      debugPrint(
        '[DeleteBand] State cleanup complete for band: $deletedBandId',
      );

      // Pop the screen first, then show snackbar on the previous screen
      if (mounted) {
        Navigator.of(context).pop();
        // Show snackbar after navigation so it appears on the underlying screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showSuccessSnackBar(context, message: '$bandName deleted');
          }
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('[DeleteBand] PostgrestException: ${e.code} - ${e.message}');
      setState(() => _isDeleting = false);
      if (mounted) {
        // Parse user-friendly error messages from RPC exceptions
        String errorMessage = e.message;
        if (errorMessage.contains('Permission denied')) {
          errorMessage = 'Only active band members can delete this band';
        } else if (errorMessage.contains('Band not found')) {
          errorMessage = 'This band no longer exists';
        }
        _showErrorSnackBar('Failed to delete band: $errorMessage');
      }
    } catch (e) {
      debugPrint('[DeleteBand] Error: $e');
      setState(() => _isDeleting = false);
      if (mounted) {
        _showErrorSnackBar('Failed to delete band');
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
      debugPrint('[Upload] User ID: $userId');
      if (userId == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName = '$userId/$timestamp.$extension';
      debugPrint('[Upload] File name: $fileName');

      final bytes = await imageFile.readAsBytes();
      debugPrint('[Upload] Bytes read: ${bytes.length}');

      await supabase.storage.from('band-avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );
      debugPrint('[Upload] Upload complete');

      final url = supabase.storage.from('band-avatars').getPublicUrl(fileName);
      debugPrint('[Upload] Public URL: $url');
      return url;
    } catch (e) {
      debugPrint('[Upload] Failed to upload image: $e');
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
          backgroundColor: context.colors.warning,
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
          backgroundColor: context.colors.warning,
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
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.colors.surface,
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
                  color: context.colors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Spacing.space16),
              Text(
                'Choose Image Source',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.space24),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    AppIcons.camera,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  'Take Photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Use camera to take a new photo',
                  style:
                      TextStyle(fontSize: 14, color: context.colors.textMuted),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: Spacing.space8),
              ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    AppIcons.image,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  'Photo Library',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Choose from your photos',
                  style:
                      TextStyle(fontSize: 14, color: context.colors.textMuted),
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

      debugPrint('[PickImage] Image selected: ${image.path}');
      final imageFile = File(image.path);
      final fileExists = await imageFile.exists();
      debugPrint('[PickImage] File exists: $fileExists');

      setState(() {
        _selectedImage = imageFile;
        _isUploadingImage = true;
        _uploadedImageUrl = null;
      });
      debugPrint('[PickImage] State updated, _selectedImage set');
      HapticFeedback.lightImpact();

      // Update draft state for instant header preview
      if (_isEditMode) {
        ref.read(draftBandProvider.notifier).setLocalImageFile(imageFile);
      }

      // Upload immediately for better UX
      debugPrint('[PickImage] Starting upload...');
      final uploadedUrl = await _uploadImageToStorage(imageFile);
      debugPrint('[PickImage] Upload result: $uploadedUrl');

      if (mounted) {
        setState(() {
          _uploadedImageUrl = uploadedUrl;
          _isUploadingImage = false;
        });
        debugPrint(
          '[PickImage] State updated after upload, _uploadedImageUrl: $uploadedUrl',
        );

        // Update draft state with uploaded URL for header preview
        if (_isEditMode && uploadedUrl != null) {
          ref.read(draftBandProvider.notifier).updateImageUrl(uploadedUrl);
          debugPrint('[PickImage] Draft state updated with URL');
        }

        if (uploadedUrl != null) {
          showSuccessSnackBar(context, message: 'Image uploaded successfully');
        } else {
          showErrorSnackBar(context, message: 'Failed to upload image');
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

  @override
  Widget build(BuildContext context) {
    final title = _isEditMode ? 'Edit Band' : 'Create New Band';
    final subtitle = _isEditMode
        ? 'Update your band details'
        : 'Set up your band and invite members';
    final submitLabel = _isEditMode ? 'Update Band' : 'Create Band';

    return Scaffold(
      backgroundColor: context.colors.background,
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
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                  color: context.colors.textSecondary,
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

                              // Timezone picker
                              _buildTimezoneSection(),
                              const SizedBox(height: Spacing.space32),

                              // Invite members section (only for create mode)
                              if (!_isEditMode) ...[
                                _buildSectionLabel('Invite Members'),
                                const SizedBox(height: Spacing.space6),
                                Text(
                                  'Add email addresses to invite members to your band',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: Spacing.space12),
                                _buildEmailInput(),
                                const SizedBox(height: Spacing.space8),
                                EmailDomainShortcutBar(
                                    controller: _emailController),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.back,
                  color: Colors.white,
                  size: 24,
                ),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: Colors.white,
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
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: context.colors.textPrimary,
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
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: context.colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: context.colors.textMuted,
        ),
        filled: true,
        fillColor: context.colors.surface,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
                      color: AppColors.primary,
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
                    color: context.colors.success,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: context.colors.background, width: 2),
                  ),
                  child: const Icon(
                    AppIcons.check,
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
                              color:
                                  context.colors.surface.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.colors.textPrimary
                                    .withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.upload_rounded,
                                color: context.colors.textPrimary
                                    .withValues(alpha: 0.5),
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
                        right:
                            colorIndex < AvatarColors.colors.length - 1 ? 8 : 0,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarColor = colorOption.tailwindClass;
                            _selectedImage = null;
                            _uploadedImageUrl = null;
                          });
                          // Update draft state for header avatar preview
                          if (_isEditMode) {
                            ref
                                .read(draftBandProvider.notifier)
                                .updateAvatarColor(colorOption.tailwindClass);
                          }
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
              Text(
                'Upload an image or choose a color for your band avatar.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Timezone entries. isHeader: true entries are rendered as disabled group labels.
  static const List<Map<String, dynamic>> _timezoneOptions = [
    // United States (first)
    {'value': null, 'label': 'United States', 'isHeader': true},
    {'value': 'America/New_York', 'label': 'New York (Eastern)'},
    {'value': 'America/Chicago', 'label': 'Chicago (Central)'},
    {'value': 'America/Denver', 'label': 'Denver (Mountain)'},
    {'value': 'America/Phoenix', 'label': 'Phoenix (Mountain – No DST)'},
    {'value': 'America/Los_Angeles', 'label': 'Los Angeles (Pacific)'},
    {'value': 'America/Anchorage', 'label': 'Anchorage (Alaska)'},
    {'value': 'Pacific/Honolulu', 'label': 'Honolulu (Hawaii-Aleutian)'},
    // Canada
    {'value': null, 'label': 'Canada', 'isHeader': true},
    {'value': 'America/Vancouver', 'label': 'Vancouver (Pacific)'},
    {'value': 'America/Edmonton', 'label': 'Edmonton (Mountain)'},
    {
      'value': 'America/Dawson_Creek',
      'label': 'Dawson Creek (Mountain – No DST)'
    },
    {'value': 'America/Creston', 'label': 'Creston (Mountain – No DST)'},
    {'value': 'America/Regina', 'label': 'Regina (Central – No DST)'},
    {'value': 'America/Toronto', 'label': 'Toronto (Eastern)'},
    {'value': 'America/Halifax', 'label': 'Halifax (Atlantic)'},
    {'value': 'America/St_Johns', 'label': "St. John's (Newfoundland)"},
    {'value': 'America/Whitehorse', 'label': 'Whitehorse (Yukon – No DST)'},
    // Europe
    {'value': null, 'label': 'Europe', 'isHeader': true},
    {'value': 'Europe/London', 'label': 'London (Western European)'},
    {'value': 'Europe/Dublin', 'label': 'Dublin (Western European)'},
    {'value': 'Europe/Lisbon', 'label': 'Lisbon (Western European)'},
    {'value': 'Europe/Madrid', 'label': 'Madrid (Central European)'},
    {'value': 'Europe/Paris', 'label': 'Paris (Central European)'},
    {'value': 'Europe/Amsterdam', 'label': 'Amsterdam (Central European)'},
    {'value': 'Europe/Berlin', 'label': 'Berlin (Central European)'},
    {'value': 'Europe/Zurich', 'label': 'Zurich (Central European)'},
    {'value': 'Europe/Rome', 'label': 'Rome (Central European)'},
    {'value': 'Europe/Stockholm', 'label': 'Stockholm (Central European)'},
  ];

  Widget _buildTimezoneSection() {
    // In create mode, the creator is always admin so always enabled
    // In edit mode, only admins/managers can edit timezone
    final bool canEdit;
    if (!_isEditMode) {
      canEdit = true;
    } else {
      final permissionsAsync = ref.watch(currentUserPermissionsProvider);
      canEdit = permissionsAsync.when(
        data: (p) => p.canEditBandSettings,
        loading: () => false,
        error: (_, __) => false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Timezone Location'),
        const SizedBox(height: Spacing.space6),
        Text(
          'Used for general formatting and calendar feeds',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.space12),
        DropdownButtonFormField<String>(
          initialValue: _timezoneOptions
                  .where((tz) => tz['value'] != null)
                  .any((tz) => tz['value'] == _selectedTimezone)
              ? _selectedTimezone
              : 'America/Chicago',
          decoration: InputDecoration(
            filled: true,
            fillColor: context.colors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.space16,
              vertical: Spacing.space12,
            ),
          ),
          dropdownColor: context.colors.surfaceElevated,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
          ),
          items: _timezoneOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final tz = entry.value;
            final isHeader = tz['isHeader'] == true;
            return DropdownMenuItem<String>(
              value: isHeader ? null : tz['value'] as String,
              enabled: !isHeader,
              child: isHeader
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index > 0)
                          Divider(
                            color: Colors.grey.shade700,
                            thickness: 0.5,
                            height: 16,
                          ),
                        Text(
                          tz['label'] as String,
                          style: TextStyle(
                            color: context.colors.primaryLight,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      tz['label'] as String,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            );
          }).toList(),
          onChanged: canEdit
              ? (value) {
                  if (value != null) {
                    setState(() => _selectedTimezone = value);
                  }
                }
              : null,
        ),
        if (!canEdit)
          Padding(
            padding: EdgeInsets.only(top: Spacing.space8),
            child: Text(
              'Only admins can change the timezone',
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 12,
              ),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: context.colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: context.colors.textMuted,
              ),
              filled: true,
              fillColor: context.colors.surface,
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
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
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
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            ),
            child: const Center(
              child: Icon(AppIcons.add, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
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
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: context.colors.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        // Delete button (edit mode only, admin only)
        if (_isEditMode) ...[
          // Only show delete button if user has canDeleteBand permission
          Builder(builder: (context) {
            final permissionsAsync = ref.watch(currentUserPermissionsProvider);
            final canExport = permissionsAsync.when(
              data: (perms) => perms.canExportBandData,
              loading: () => false,
              error: (_, __) => false,
            );
            final canDelete = permissionsAsync.when(
              data: (perms) => perms.canDeleteBand,
              loading: () => false,
              error: (_, __) => false,
            );
            if (!canExport) return const SizedBox.shrink();
            final isBusy =
                _isSubmitting || _isDeleting || _isExporting || _isImporting;
            return Column(
              children: [
                const SizedBox(height: Spacing.space24),
                // Backup / Restore entry point
                OutlinedButton.icon(
                  onPressed: isBusy ? null : _showBackupRestoreSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        width: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  icon: (_isExporting || _isImporting)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary),
                          ),
                        )
                      : const Icon(AppIcons.rotateCcw, size: 15),
                  label: Text(
                    canDelete ? 'Backup / Restore Data' : 'Backup Data',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (canDelete) ...[
                  const SizedBox(height: Spacing.space8),
                  TextButton(
                    onPressed:
                        (_isSubmitting || _isDeleting) ? null : _deleteBand,
                    child: _isDeleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          )
                        : const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: AppColors.primary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                  ),
                ],
              ],
            );
          }),
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
        color: context.colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            email,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.33,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              AppIcons.close,
              size: 16,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backup / Restore bottom-sheet panel (one side of the two-column sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _BackupSheetPanel extends StatelessWidget {
  const _BackupSheetPanel({
    required this.icon,
    required this.label,
    required this.description,
    required this.bullets,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final List<String> bullets;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Outlined action button
        OutlinedButton.icon(
          onPressed: isLoading ? null : onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.6), width: 1),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          icon: isLoading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              : Icon(icon, size: 16),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Description
        Text(
          description,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        // Bullet list
        ...bullets.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ',
                    style: TextStyle(
                        fontSize: 15, color: context.colors.textPrimary)),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.colors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
