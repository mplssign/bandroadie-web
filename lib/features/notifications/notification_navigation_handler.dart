import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/models/gig.dart';
import '../../app/models/rehearsal.dart';
import '../../app/services/supabase_client.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../gigs/widgets/view_gig_drawer.dart';
import '../home/widgets/animated_bottom_nav_bar.dart' show NavTabIndex;
import '../rehearsals/widgets/view_rehearsal_drawer.dart';
import '../shell/tab_provider.dart';

// ============================================================================
// NOTIFICATION NAVIGATION HANDLER
// Handles navigation from push notification taps
// ============================================================================

class NotificationNavigationHandler {
  /// Navigate to the appropriate screen based on notification data
  static Future<void> navigate(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) async {
    try {
      final notificationType = data['type'] as String?;
      final bandId = data['band_id'] as String?;

      if (notificationType == null || bandId == null) {
        _showError(
          context,
          'Unable to open notification: missing required data',
        );
        return;
      }

      // Switch band context if needed
      final activeBandState = ref.read(activeBandProvider);
      if (activeBandState.activeBand?.id != bandId) {
        final targetBand =
            activeBandState.userBands.where((b) => b.id == bandId).firstOrNull;
        if (targetBand == null) {
          if (!context.mounted) return;
          _showError(context, 'You no longer have access to this band');
          return;
        }
        await ref.read(activeBandProvider.notifier).selectBand(targetBand);
      }

      if (!context.mounted) return;

      // Navigate based on notification type
      switch (notificationType) {
        case 'gig_created':
        case 'potential_gig_created':
          await _navigateToGig(context, ref, data, bandId);
          break;
        case 'rehearsal_created':
          await _navigateToRehearsal(context, ref, data, bandId);
          break;
        case 'blockout_created':
          ref.read(currentTabProvider.notifier).setTab(NavTabIndex.calendar);
          break;
        default:
          _showError(context, 'Unknown notification type: $notificationType');
      }
    } catch (e) {
      debugPrint('[NotificationNavigationHandler] Error: $e');
      if (context.mounted) {
        _showError(context, 'Unable to open notification');
      }
    }
  }

  static Future<void> _navigateToGig(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
    String bandId,
  ) async {
    final gigId = data['gig_id'] as String?;
    if (gigId == null) {
      _showError(context, 'Gig information not found');
      return;
    }

    try {
      // Fetch gig by ID
      final response = await supabase.from('gigs').select('''
            *,
            gig_dates (
              id,
              gig_id,
              date,
              start_time,
              created_at,
              updated_at
            )
          ''').eq('id', gigId).eq('band_id', bandId).maybeSingle();

      if (response == null) {
        if (context.mounted) {
          _showError(context, 'Gig not found');
        }
        return;
      }

      final gig = Gig.fromJson(response);

      // Get band timezone and permissions
      final activeBandId = ref.read(activeBandProvider).activeBand?.id;
      if (activeBandId == null) {
        if (context.mounted) {
          _showError(context, 'No active band selected');
        }
        return;
      }

      // Fetch band details to get timezone
      final bandResponse = await supabase
          .from('bands')
          .select('timezone')
          .eq('id', activeBandId)
          .maybeSingle();

      final bandTimezone =
          (bandResponse?['timezone'] as String?) ?? 'America/Chicago';

      if (context.mounted) {
        await ViewGigDrawer.show(
          context,
          gig: gig,
          bandTimezone: bandTimezone,
          canEdit: false, // View-only from notifications (no edit flow wired)
          onEdit: () {},
        );
      }
    } catch (e) {
      debugPrint('[NotificationNavigationHandler] Error fetching gig: $e');
      if (context.mounted) {
        _showError(context, 'Unable to load gig');
      }
    }
  }

  static Future<void> _navigateToRehearsal(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
    String bandId,
  ) async {
    final rehearsalId = data['rehearsal_id'] as String?;
    if (rehearsalId == null) {
      _showError(context, 'Rehearsal information not found');
      return;
    }

    try {
      // Fetch rehearsal by ID
      final response = await supabase.from('rehearsals').select('''
            *,
            rehearsal_dates (
              id,
              rehearsal_id,
              date,
              start_time,
              created_at,
              updated_at
            )
          ''').eq('id', rehearsalId).eq('band_id', bandId).maybeSingle();

      if (response == null) {
        if (context.mounted) {
          _showError(context, 'Rehearsal not found');
        }
        return;
      }

      final rehearsal = Rehearsal.fromJson(response);

      // Get band timezone and permissions
      final activeBandId = ref.read(activeBandProvider).activeBand?.id;
      if (activeBandId == null) {
        if (context.mounted) {
          _showError(context, 'No active band selected');
        }
        return;
      }

      // Fetch band details to get timezone
      final bandResponse = await supabase
          .from('bands')
          .select('timezone')
          .eq('id', activeBandId)
          .maybeSingle();

      final bandTimezone =
          (bandResponse?['timezone'] as String?) ?? 'America/Chicago';

      if (context.mounted) {
        await ViewRehearsalDrawer.show(
          context,
          rehearsal: rehearsal,
          bandTimezone: bandTimezone,
          canEdit: false, // View-only from notifications (no edit flow wired)
          onEdit: () {},
        );
      }
    } catch (e) {
      debugPrint(
          '[NotificationNavigationHandler] Error fetching rehearsal: $e');
      if (context.mounted) {
        _showError(context, 'Unable to load rehearsal');
      }
    }
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    showErrorSnackBar(
      context,
      message: message,
    );
  }
}
