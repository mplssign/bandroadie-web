import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import 'notification_controller.dart';
import 'widgets/notification_card.dart';

// ============================================================================
// NOTIFICATIONS SCREEN
// In-app activity feed showing all notifications
// ============================================================================

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load notifications on screen open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationListProvider.notifier).loadInitial();
    });

    // Infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationListProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        title: Text(
          'Activity',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () {
                ref.read(notificationListProvider.notifier).markAllAsRead();
              },
              child: Text(
                'Mark all read',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(NotificationListState state) {
    if (state.isLoading && state.notifications.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (state.error != null && state.notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              state.error!,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.space16),
            TextButton(
              onPressed: () {
                ref.read(notificationListProvider.notifier).refresh();
              },
              child: Text(
                'Try again',
                style: AppTextStyles.body.copyWith(color: AppColors.accent),
              ),
            ),
          ],
        ),
      );
    }

    if (state.notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              'No notifications yet',
              style: AppTextStyles.title3.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.space8),
            Text(
              "We'll let you know when something happens",
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationListProvider.notifier).refresh(),
      color: AppColors.accent,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(Spacing.pagePadding),
        itemCount: state.notifications.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.notifications.length) {
            return const Padding(
              padding: EdgeInsets.all(Spacing.space16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }

          final notification = state.notifications[index];
          return NotificationCard(
            notification: notification,
            onTap: () {
              // Handle deep link navigation
              final deepLink = notification.deepLink;
              if (deepLink != null) {
                // TODO: Navigate to deep link
                debugPrint('[NotificationsScreen] Navigate to: $deepLink');
              }
            },
          );
        },
      ),
    );
  }
}
