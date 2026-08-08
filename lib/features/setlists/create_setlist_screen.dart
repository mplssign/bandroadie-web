import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';

// ============================================================================
// CREATE SETLIST SCREEN
// Placeholder screen for creating a new setlist.
// Will be fully implemented when Supabase wiring is added.
// ============================================================================

class CreateSetlistScreen extends StatelessWidget {
  const CreateSetlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.appBarBg,
        title: Text('New Setlist', style: AppTextStyles.title3),
        leading: AppIconButton(
          icon: AppIcons.close,
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.pagePadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.setlists,
                color: context.colors.textMuted,
                size: 64,
              ),
              const SizedBox(height: Spacing.space24),
              Text('Create Setlist', style: AppTextStyles.title3),
              const SizedBox(height: Spacing.space12),
              Text(
                'Setlist creation form coming soon.\nThis placeholder will be replaced with the full form.',
                textAlign: TextAlign.center,
                style: AppTextStyles.callout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
