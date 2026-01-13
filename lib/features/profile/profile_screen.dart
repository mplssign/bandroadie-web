import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/user_profile.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';

// ============================================================================
// PROFILE SCREEN
// Displays and allows editing of the user's profile information.
// ============================================================================

/// Provider to fetch user profile from Supabase
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('users')
      .select()
      .eq('id', userId)
      .maybeSingle();

  if (response == null) return null;
  return UserProfile.fromJson(response);
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _populateFields(UserProfile profile) {
    _firstNameController.text = profile.firstName ?? '';
    _lastNameController.text = profile.lastName ?? '';
    _phoneController.text = profile.phone ?? '';
    _cityController.text = profile.city ?? '';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      await supabase
          .from('users')
          .update({
            'first_name': _firstNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'city': _cityController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      // Refresh the profile data
      ref.invalidate(userProfileProvider);

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });

      if (mounted) {
        showSuccessSnackBar(context, message: 'Profile updated');
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showErrorSnackBar(context, message: 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        title: Text('My Profile', style: AppTextStyles.title3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              onPressed: () {
                final profile = profileAsync.value;
                if (profile != null) {
                  _populateFields(profile);
                  setState(() => _isEditing = true);
                }
              },
            )
          else
            TextButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.space24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: Spacing.space16),
                Text('Error loading profile', style: AppTextStyles.title3),
                const SizedBox(height: Spacing.space8),
                Text(
                  error.toString(),
                  style: AppTextStyles.callout,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.space24),
                ElevatedButton(
                  onPressed: () => ref.invalidate(userProfileProvider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Text('Profile not found', style: AppTextStyles.callout),
            );
          }

          return _isEditing
              ? _buildEditForm(profile)
              : _buildProfileView(profile);
        },
      ),
    );
  }

  Widget _buildProfileView(UserProfile profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar and name section
          Center(
            child: Column(
              children: [
                // Avatar circle
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.2),
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(profile),
                      style: AppTextStyles.title3.copyWith(
                        fontSize: 32,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  profile.fullName,
                  style: AppTextStyles.title3.copyWith(fontSize: 24),
                ),
                const SizedBox(height: Spacing.space4),
                Text(profile.email, style: AppTextStyles.callout),
              ],
            ),
          ),

          const SizedBox(height: Spacing.space32),
          const Divider(color: AppColors.borderMuted),
          const SizedBox(height: Spacing.space24),

          // Profile details
          _ProfileRow(label: 'First Name', value: profile.firstName ?? '—'),
          _ProfileRow(label: 'Last Name', value: profile.lastName ?? '—'),
          _ProfileRow(label: 'Phone', value: profile.phone ?? '—'),
          _ProfileRow(label: 'City', value: profile.city ?? '—'),
          _ProfileRow(
            label: 'Member Since',
            value: _formatDate(profile.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm(UserProfile profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.space24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Email (read-only)
            _buildReadOnlyField('Email', profile.email),
            const SizedBox(height: Spacing.space16),

            // First Name
            _buildTextField(
              controller: _firstNameController,
              label: 'First Name',
              hint: 'Enter your first name',
            ),
            const SizedBox(height: Spacing.space16),

            // Last Name
            _buildTextField(
              controller: _lastNameController,
              label: 'Last Name',
              hint: 'Enter your last name',
            ),
            const SizedBox(height: Spacing.space16),

            // Phone
            _buildTextField(
              controller: _phoneController,
              label: 'Phone',
              hint: 'Enter your phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: Spacing.space16),

            // City
            _buildTextField(
              controller: _cityController,
              label: 'City',
              hint: 'Enter your city',
            ),

            const SizedBox(height: Spacing.space32),

            // Cancel button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => setState(() => _isEditing = false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.borderMuted),
                  padding: const EdgeInsets.symmetric(
                    vertical: Spacing.space16,
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
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
        const SizedBox(height: Spacing.space8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.borderMuted),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.space16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(
              color: AppColors.borderMuted.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            value,
            style: AppTextStyles.callout.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _getInitials(UserProfile profile) {
    final first = profile.firstName?.isNotEmpty == true
        ? profile.firstName![0].toUpperCase()
        : '';
    final last = profile.lastName?.isNotEmpty == true
        ? profile.lastName![0].toUpperCase()
        : '';
    if (first.isEmpty && last.isEmpty) {
      return profile.email.isNotEmpty ? profile.email[0].toUpperCase() : '?';
    }
    return '$first$last';
  }

  String _formatDate(DateTime date) {
    final months = [
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.callout.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTextStyles.callout.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
