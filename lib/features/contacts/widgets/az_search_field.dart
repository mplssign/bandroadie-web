import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

// ============================================================================
// AZ SEARCH FIELD
// Shared search bar used by the A-Z list segments (Venues, Band, Contacts).
// ============================================================================

class AzSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String currentQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const AzSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.currentQuery,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: context.colors.textSecondary,
          fontSize: AppFontSizes.body,
        ),
        prefixIcon: Icon(
          AppIcons.search,
          color: context.colors.textSecondary,
        ),
        suffixIcon: currentQuery.isNotEmpty
            ? IconButton(
                icon: Icon(
                  AppIcons.close,
                  color: context.colors.textSecondary,
                ),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: context.colors.border,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: context.colors.border,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
      ),
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: AppFontSizes.body,
      ),
      onChanged: onChanged,
    );
  }
}
