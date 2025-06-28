import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart' as app_logger;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notification channel IDs
  static const String _syncChannelId = 'sync_channel';
  static const String _syncChannelName = 'File Sync';
  static const String _syncChannelDescription = 'Notifications for file synchronization';

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize plugin
      const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      
      await _notifications.initialize(initializationSettings);

      // Create notification channel for Android
      const androidChannel = AndroidNotificationChannel(
        _syncChannelId,
        _syncChannelName,
        description: _syncChannelDescription,
        importance: Importance.defaultImportance,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      _initialized = true;
      app_logger.Logger.info('📱 Notification service initialized');
    } catch (e) {
      app_logger.Logger.error('Failed to initialize notification service', error: e);
    }
  }

  /// Show sync started notification
  static Future<void> showSyncStarted() async {
    await _showNotification(
      id: 1,
      title: 'simplySync',
      body: 'File synchronization started...',
      ongoing: true,
      showProgress: true,
      progress: 0,
      maxProgress: 100,
    );
  }

  /// Show sync progress notification
  static Future<void> showSyncProgress({
    required int currentFile,
    required int totalFiles,
    required String fileName,
  }) async {
    final progress = ((currentFile / totalFiles) * 100).round();
    await _showNotification(
      id: 1,
      title: 'simplySync',
      body: 'Syncing $fileName ($currentFile/$totalFiles)',
      ongoing: true,
      showProgress: true,
      progress: progress,
      maxProgress: 100,
    );
  }

  /// Show sync completed notification
  static Future<void> showSyncCompleted({
    required int syncedCount,
    required int errorCount,
  }) async {
    // First, clear the progress notification
    await clearSyncProgress();
    
    String body;
    if (errorCount == 0) {
      body = 'Successfully synced $syncedCount files';
    } else {
      body = 'Synced $syncedCount files with $errorCount errors';
    }

    await _showNotification(
      id: 2,
      title: 'simplySync Complete',
      body: body,
      ongoing: false,
      autoCancel: true,
    );
  }

  /// Show sync failed notification
  static Future<void> showSyncFailed(String error) async {
    // First, clear the progress notification
    await clearSyncProgress();
    
    await _showNotification(
      id: 3,
      title: 'simplySync Failed',
      body: 'Sync failed: $error',
      ongoing: false,
      autoCancel: true,
    );
  }

  /// Show scheduled sync notification
  static Future<void> showScheduledSyncEnabled(int intervalMinutes) async {
    await _showNotification(
      id: 4,
      title: 'simplySync Scheduled',
      body: 'Background sync enabled (every $intervalMinutes minutes)',
      ongoing: false,
      autoCancel: true,
    );
  }

  /// Show scheduled sync disabled notification
  static Future<void> showScheduledSyncDisabled() async {
    await _showNotification(
      id: 5,
      title: 'simplySync',
      body: 'Background sync disabled',
      ongoing: false,
      autoCancel: true,
    );
  }

  /// Clear sync progress notification
  static Future<void> clearSyncProgress() async {
    await _notifications.cancel(1);
  }

  /// Clear all notifications
  static Future<void> clearAll() async {
    await _notifications.cancelAll();
  }

  /// Show a notification with the given parameters
  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    bool ongoing = false,
    bool autoCancel = false,
    bool showProgress = false,
    int progress = 0,
    int maxProgress = 100,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        _syncChannelId,
        _syncChannelName,
        channelDescription: _syncChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: ongoing,
        autoCancel: autoCancel,
        showProgress: showProgress,
        progress: showProgress ? progress : 0,
        maxProgress: showProgress ? maxProgress : 0,
        indeterminate: showProgress && progress == 0,
        icon: '@mipmap/ic_launcher',
      );

      final notificationDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      app_logger.Logger.error('Failed to show notification', error: e);
    }
  }

  /// Request notification permissions (Android 13+)
  static Future<bool> requestNotificationPermissions() async {
    try {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        app_logger.Logger.info('📱 Notification permission granted: $granted');
        return granted ?? false;
      }
      return true; // Assume granted for older Android versions
    } catch (e) {
      app_logger.Logger.error('Failed to request notification permissions', error: e);
      return false;
    }
  }
}
