import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/app_notification.dart';
import 'models/notification_preferences.dart';

// ============================================================================
// NOTIFICATION REPOSITORY
// Handles Supabase queries for notifications and preferences
// ============================================================================

class NotificationRepository {
  final SupabaseClient _supabase;

  NotificationRepository(this._supabase);

  // --------------------------------------------------------------------------
  // NOTIFICATIONS
  // --------------------------------------------------------------------------

  /// Fetch notifications for the current user
  Future<List<AppNotification>> fetchNotifications({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    var baseQuery = _supabase.from('notifications').select();

    if (unreadOnly) {
      baseQuery = baseQuery.isFilter('read_at', null);
    }

    final response = await baseQuery
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => AppNotification.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get unread notification count
  Future<int> getUnreadCount() async {
    final response = await _supabase.rpc('get_unread_notification_count');
    return response as int? ?? 0;
  }

  /// Mark a single notification as read
  Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId);
  }

  /// Mark all notifications as read
  Future<int> markAllAsRead() async {
    final count = await _supabase.rpc('mark_all_notifications_read');
    return count as int? ?? 0;
  }

  // --------------------------------------------------------------------------
  // DEVICE TOKENS
  // --------------------------------------------------------------------------

  /// Register or update FCM token for this device
  Future<String?> upsertDeviceToken({
    required String fcmToken,
    required String platform,
    String? deviceName,
  }) async {
    final response = await _supabase.rpc(
      'upsert_device_token',
      params: {
        'p_fcm_token': fcmToken,
        'p_platform': platform,
        'p_device_name': deviceName,
      },
    );
    return response as String?;
  }

  /// Remove a device token (on logout)
  Future<void> removeDeviceToken(String fcmToken) async {
    await _supabase.from('device_tokens').delete().eq('fcm_token', fcmToken);
  }

  // --------------------------------------------------------------------------
  // PREFERENCES
  // --------------------------------------------------------------------------

  /// Get or create notification preferences for the current user
  Future<NotificationPreferences> getOrCreatePreferences() async {
    final response = await _supabase.rpc(
      'get_or_create_notification_preferences',
    );
    return NotificationPreferences.fromJson(response as Map<String, dynamic>);
  }

  /// Update notification preferences
  Future<void> updatePreferences(NotificationPreferences prefs) async {
    await _supabase
        .from('notification_preferences')
        .update({
          'notifications_enabled': prefs.notificationsEnabled,
          'gigs_enabled': prefs.gigsEnabled,
          'potential_gigs_enabled': prefs.potentialGigsEnabled,
          'rehearsals_enabled': prefs.rehearsalsEnabled,
          'blockouts_enabled': prefs.blockoutsEnabled,
          // Keep legacy fields for backwards compatibility
          'setlist_updates': prefs.setlistUpdates,
          'availability_requests': prefs.availabilityRequests,
          'member_updates': prefs.memberUpdates,
          'push_enabled': prefs.pushEnabled,
          'in_app_enabled': prefs.inAppEnabled,
        })
        .eq('user_id', prefs.userId);
  }
}
