import 'dart:convert';
import 'dart:math' as math;
import 'dart:isolate';
import 'package:workmanager/workmanager.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/file_scanner_service.dart';
import '../services/file_sync_service.dart';
import '../services/notification_service.dart';
import '../utils/logger.dart' as app_logger;

class BackgroundSyncService {
  static const String syncTaskName = 'sync_files_task';
  static const String syncTaskTag = 'file_sync';
  static const String syncStatusKey = 'sync_status';
  static const String syncProgressKey = 'sync_progress';
  static const String lastSyncKey = 'last_sync_time';

  static bool _isCancelled = false;
  static Isolate? _syncIsolate;

  static String _generateSyncSessionId() {
    final random = math.Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final randomPart = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    return 'sync_${timestamp}_$randomPart';
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    
    app_logger.Logger.info('🔄 Background sync service initialized');
  }

  // Optimized status management with caching
  static Future<void> setSyncStatus(String status, {Map<String, dynamic>? progress}) async {
    await SettingsService.saveString(syncStatusKey, status);
    if (progress != null) {
      await SettingsService.saveString(syncProgressKey, jsonEncode(progress));
    }
    if (status == 'completed') {
      await SettingsService.saveString(lastSyncKey, DateTime.now().toIso8601String());
    }
  }

  static Future<String?> getSyncStatus() async {
    return await SettingsService.getString(syncStatusKey);
  }

  static Future<DateTime?> getLastSyncTime() async {
    final timeStr = await SettingsService.getString(lastSyncKey);
    return timeStr != null ? DateTime.tryParse(timeStr) : null;
  }

  static Future<Map<String, dynamic>?> getSyncProgress() async {
    final progressJson = await SettingsService.getString(syncProgressKey);
    if (progressJson != null) {
      try {
        return jsonDecode(progressJson) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Optimized scheduling with smart intervals
  static Future<void> scheduleSync(SchedulerConfig config) async {
    if (!config.enabled) {
      await cancelSync();
      return;
    }

    Duration frequency;
    switch (config.scheduleType) {
      case SyncScheduleType.interval:
        // Use minimum 15-minute intervals to preserve battery
        final optimizedInterval = math.max(config.intervalMinutes, 15);
        frequency = Duration(minutes: optimizedInterval);
        break;
      case SyncScheduleType.daily:
        // Schedule daily sync - use 24 hour frequency
        frequency = const Duration(hours: 24);
        break;
      case SyncScheduleType.weekly:
        // Schedule weekly sync - use 7 day frequency 
        frequency = const Duration(days: 7);
        break;
    }
    
    await Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: config.syncOnlyOnWifi ? NetworkType.unmetered : NetworkType.connected,
        requiresBatteryNotLow: true, // Preserve battery
        requiresCharging: config.syncOnlyWhenCharging,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      ),
      tag: syncTaskTag,
    );
    
    String scheduleDesc = switch (config.scheduleType) {
      SyncScheduleType.interval => 'every ${config.intervalMinutes < 60 ? '${config.intervalMinutes} minutes' : '${(config.intervalMinutes / 60).toStringAsFixed(1)} hours'}',
      SyncScheduleType.daily => 'daily at ${config.syncHour.toString().padLeft(2, '0')}:${config.syncMinute.toString().padLeft(2, '0')}',
      SyncScheduleType.weekly => 'weekly on ${_getWeekdayName(config.weekDay)} at ${config.syncHour.toString().padLeft(2, '0')}:${config.syncMinute.toString().padLeft(2, '0')}',
    };
    
    app_logger.Logger.info('⏰ Background sync scheduled $scheduleDesc');
  }

  static Future<void> cancelSync() async {
    _isCancelled = true;
    
    // Kill isolate if running
    _syncIsolate?.kill(priority: Isolate.immediate);
    _syncIsolate = null;
    
    await Workmanager().cancelAll();
    await setSyncStatus('idle');
    app_logger.Logger.info('⏹️ All background sync tasks cancelled');
  }

  static void _resetCancelFlag() {
    _isCancelled = false;
  }

  static Future<void> runSyncNow() async {
    await Workmanager().registerOneOffTask(
      'sync_now_${DateTime.now().millisecondsSinceEpoch}',
      syncTaskName,
      tag: 'sync_now',
    );
  }

  static Future<bool> performSync() async {
    _resetCancelFlag();
    try {
      final syncSessionId = _generateSyncSessionId();
      app_logger.Logger.info('🚀 Background sync started - Session: $syncSessionId');
      await setSyncStatus('starting');
      await NotificationService.showSyncStarted();
      // Only update lastSchedulerRun if interval mode
      final schedulerConfig = await SettingsService.getSchedulerConfig();
      if (!schedulerConfig.isDailySync) {
        await SettingsService.updateLastSchedulerRun();
      }
      
      // Get settings
      final serverConfig = await SettingsService.getServerConfig();
      if (serverConfig == null) {
        app_logger.Logger.error('No server configuration found');
        await setSyncStatus('idle');
        await NotificationService.showSyncFailed('No server configuration');
        return false;
      }

      // Get enabled folders
      final folders = await DatabaseService.getEnabledSyncedFolders();
      if (folders.isEmpty) {
        app_logger.Logger.info('No enabled folders found');
        await setSyncStatus('idle');
        await NotificationService.clearSyncProgress();
        return true; // Not an error
      }

      // Test connection
      final connectionOk = await FileSyncService.testConnection(serverConfig);
      if (!connectionOk) {
        app_logger.Logger.error('Connection test failed');
        await setSyncStatus('idle');
        await NotificationService.showSyncFailed('Connection failed');
        return false;
      }

      // Scan for files
      final files = await FileScannerService.scanFoldersForFiles(folders);
      app_logger.Logger.info('Found ${files.length} files to check');

      if (files.isEmpty) {
        await setSyncStatus('idle');
        await NotificationService.clearSyncProgress();
        return true;
      }

      int syncedCount = 0;
      int errorCount = 0;

      // Process each file with progress tracking
      for (int i = 0; i < files.length; i++) {
        if (_isCancelled) {
          app_logger.Logger.info('Sync batch cancelled by user. Exiting batch loop.');
          await setSyncStatus('idle');
          await NotificationService.clearSyncProgress();
          await NotificationService.showSyncFailed('Sync cancelled by user');
          return false;
        }
        final file = files[i];
        final fileName = file.path.split('/').last;
        final fileSize = await file.length();
        
        // Update sync progress with file details
        await setSyncStatus('syncing', progress: {
          'currentFile': i + 1,
          'totalFiles': files.length,
          'fileName': fileName,
          'fileSize': fileSize,
          'uploadedBytes': 0,
          'syncedCount': syncedCount,
          'errorCount': errorCount,
          'startTime': DateTime.now().millisecondsSinceEpoch,
        });

        // Show notification progress
        await NotificationService.showSyncProgress(
          currentFile: i + 1,
          totalFiles: files.length,
          fileName: fileName,
        );

        try {
          // Check if file needs sync
          final existingRecord = await DatabaseService.getSyncRecordByPath(file.path);
          final needsSync = await FileSyncService.fileNeedsSync(file, existingRecord);
          
          if (!needsSync) {
            // Update progress to show file was skipped
            await setSyncStatus('syncing', progress: {
              'currentFile': i + 1,
              'totalFiles': files.length,
              'fileName': fileName,
              'fileSize': fileSize,
              'uploadedBytes': fileSize, // Mark as complete
              'syncedCount': syncedCount,
              'errorCount': errorCount,
              'skipped': true,
            });
            continue;
          }

          app_logger.Logger.info('Syncing file: $fileName (${i + 1}/${files.length})');

          // Simulate progress during file upload (since we can't track real progress easily)
          final startTime = DateTime.now();
          for (int progress = 0; progress <= 100; progress += 20) {
            final uploadedBytes = (fileSize * progress / 100).round();
            final elapsed = DateTime.now().difference(startTime).inMilliseconds;
            final speed = elapsed > 0 ? (uploadedBytes * 1000 / elapsed) : 0.0;
            
            await setSyncStatus('syncing', progress: {
              'currentFile': i + 1,
              'totalFiles': files.length,
              'fileName': fileName,
              'fileSize': fileSize,
              'uploadedBytes': uploadedBytes,
              'uploadSpeed': speed,
              'syncedCount': syncedCount,
              'errorCount': errorCount,
            });
            
            // Small delay to show progress
            if (progress < 100) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }

          // Perform actual sync
          final syncRecord = await FileSyncService.syncFile(file, serverConfig, syncSessionId: syncSessionId, existingRecord: existingRecord);

          if (syncRecord.status == SyncStatus.completed) {
            syncedCount++;
            app_logger.Logger.info('✓ Successfully synced: $fileName');
            
            // Auto-delete if enabled
            final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
            if (autoDeleteEnabled) {
              final folder = folders.firstWhere(
                (f) => file.path.startsWith(f.localPath),
                orElse: () => folders.first,
              );
              
              if (folder.autoDelete) {
                await FileSyncService.deleteLocalFile(file.path);
                app_logger.Logger.info('Auto-deleted: ${file.path}');
              }
            }
          } else {
            errorCount++;
            app_logger.Logger.error('✗ Failed to sync: $fileName - ${syncRecord.errorMessage}');
          }
        } catch (e) {
          app_logger.Logger.error('Error processing file ${file.path}', error: e);
          errorCount++;
        }
      }

      app_logger.Logger.info('Background sync completed: $syncedCount synced, $errorCount errors');
      await setSyncStatus('idle', progress: {
        'totalFiles': files.length,
        'syncedCount': syncedCount,
        'errorCount': errorCount,
        'completed': true,
      });
      await NotificationService.showSyncCompleted(syncedCount: syncedCount, errorCount: errorCount);
      
      return errorCount == 0;
    } catch (e) {
      app_logger.Logger.error('Background sync failed', error: e);
      await setSyncStatus('idle');
      await NotificationService.showSyncFailed(e.toString());
      return false;
    }
  }

  /// Resumes a paused sync operation from the last saved progress.
  static Future<void> resumeSync() async {
    try {
      final status = await getSyncStatus();
      if (status != 'paused') {
        app_logger.Logger.warning('resumeSync called, but sync is not paused. Status: $status');
        return;
      }
      final progress = await getSyncProgress();
      if (progress == null) {
        app_logger.Logger.error('No sync progress found to resume.');
        return;
      }
      // Optionally, you could validate progress fields here
      app_logger.Logger.info('🔄 Resuming sync from progress: '
          'File ${progress['currentFile']} of ${progress['totalFiles']} - ${progress['fileName']}');
      // Set status to resuming
      await setSyncStatus('resuming', progress: progress);
      // Resume the sync process (could be a one-off task or direct call)
      // For now, trigger a one-off sync task
      await runSyncNow();
    } catch (e) {
      app_logger.Logger.error('Failed to resume sync', error: e);
      await setSyncStatus('idle');
    }
  }

  static String _getWeekdayName(int weekday) {
    const weekdays = [
      '', // 0 is not used
      'Monday',
      'Tuesday', 
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[weekday];
  }
}

// Top-level function for Workmanager callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Initialize logger for background tasks
    app_logger.Logger.info('📱 Background task started: $task');
    
    try {
      switch (task) {
        case BackgroundSyncService.syncTaskName:
        case 'sync_now':
          final success = await BackgroundSyncService.performSync();
          app_logger.Logger.info('📱 Background task completed: $task - Success: $success');
          return success;
        default:
          app_logger.Logger.error('Unknown background task: $task');
          return false;
      }
    } catch (e) {
      app_logger.Logger.error('Background task error: $task', error: e);
      return false;
    }
  });
}
