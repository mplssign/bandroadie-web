import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_notification.dart';
import 'notification_preferences_controller.dart';

// ============================================================================
// NOTIFICATION CONTROLLER
// Manages notification state with Riverpod
// ============================================================================

/// State for the notification list
class NotificationListState {
  final List<AppNotification> notifications;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final int unreadCount;

  const NotificationListState({
    this.notifications = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.unreadCount = 0,
  });

  NotificationListState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    bool? hasMore,
    String? error,
    int? unreadCount,
  }) {
    return NotificationListState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

/// Provider for unread count (lightweight, refreshable)
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.getUnreadCount();
});

/// Provider for notification list with pagination
final notificationListProvider =
    NotifierProvider<NotificationListNotifier, NotificationListState>(
      NotificationListNotifier.new,
    );

class NotificationListNotifier extends Notifier<NotificationListState> {
  static const _pageSize = 20;

  @override
  NotificationListState build() {
    return const NotificationListState();
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final repository = ref.read(notificationRepositoryProvider);
      final notifications = await repository.fetchNotifications(
        limit: _pageSize,
      );
      final unreadCount = await repository.getUnreadCount();

      state = state.copyWith(
        notifications: notifications,
        isLoading: false,
        hasMore: notifications.length >= _pageSize,
        unreadCount: unreadCount,
      );
    } catch (e) {
      debugPrint('[NotificationListNotifier] Error loading: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load notifications',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final repository = ref.read(notificationRepositoryProvider);
      final notifications = await repository.fetchNotifications(
        limit: _pageSize,
        offset: state.notifications.length,
      );

      state = state.copyWith(
        notifications: [...state.notifications, ...notifications],
        isLoading: false,
        hasMore: notifications.length >= _pageSize,
      );
    } catch (e) {
      debugPrint('[NotificationListNotifier] Error loading more: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = const NotificationListState();
    await loadInitial();
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      final repository = ref.read(notificationRepositoryProvider);
      await repository.markAsRead(notificationId);

      // Update local state
      final updated = state.notifications.map((n) {
        if (n.id == notificationId && !n.isRead) {
          return n.copyWith(readAt: DateTime.now());
        }
        return n;
      }).toList();

      state = state.copyWith(
        notifications: updated,
        unreadCount: (state.unreadCount - 1).clamp(0, state.unreadCount),
      );

      // Refresh the count provider
      ref.invalidate(unreadNotificationCountProvider);
    } catch (e) {
      debugPrint('[NotificationListNotifier] Error marking as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final repository = ref.read(notificationRepositoryProvider);
      await repository.markAllAsRead();

      // Update local state
      final now = DateTime.now();
      final updated = state.notifications.map((n) {
        if (!n.isRead) {
          return n.copyWith(readAt: now);
        }
        return n;
      }).toList();

      state = state.copyWith(notifications: updated, unreadCount: 0);

      // Refresh the count provider
      ref.invalidate(unreadNotificationCountProvider);
    } catch (e) {
      debugPrint('[NotificationListNotifier] Error marking all as read: $e');
    }
  }
}
