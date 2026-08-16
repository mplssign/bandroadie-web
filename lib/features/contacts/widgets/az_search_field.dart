import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';

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
    return AppTextField(
      controller: controller,
      hintText: hintText,
      maxLines: 1,
      prefixIcon: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Icon(
          AppIcons.search,
          size: 22,
          color: context.colors.textSecondary,
        ),
      ),
      suffixIcon: currentQuery.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 20,
                  color: context.colors.textSecondary,
                ),
              ),
            )
          : null,
      onChanged: onChanged,
    );
  }
}
