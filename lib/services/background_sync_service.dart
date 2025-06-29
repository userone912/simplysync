import 'dart:convert';
import 'dart:math';
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

  static bool _isCancelled = false;

  static String _generateSyncSessionId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final randomPart = List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
    return 'sync_${timestamp}_$randomPart';
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );
    
    // Initialize notification service for background tasks
    // await NotificationService.initialize();
    app_logger.Logger.info('🔄 Background sync service initialized');
  }

  static Future<void> setSyncStatus(String status, {Map<String, dynamic>? progress}) async {
    await SettingsService.saveString(syncStatusKey, status);
    if (progress != null) {
      await SettingsService.saveString(syncProgressKey, jsonEncode(progress));
    }
  }

  static Future<String?> getSyncStatus() async {
    return await SettingsService.getString(syncStatusKey);
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

  static Future<void> scheduleSync(SchedulerConfig config) async {
    if (!config.enabled) {
      await cancelSync();
      // await NotificationService.showScheduledSyncDisabled();
      return;
    }

    await Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: Duration(minutes: config.intervalMinutes),
      constraints: Constraints(
        networkType: config.syncOnlyOnWifi ? NetworkType.unmetered : NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: config.syncOnlyWhenCharging,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true,
      ),
      tag: syncTaskTag,
    );
    
    // await NotificationService.showScheduledSyncEnabled(config.intervalMinutes);
    app_logger.Logger.info('⏰ Background sync scheduled every ${config.intervalMinutes} minutes');
  }

  static Future<void> cancelSync() async {
    _isCancelled = true;
    await Workmanager().cancelAll(); // Cancel all background tasks, not just by tag
    await setSyncStatus('idle'); // Explicitly set status to idle
    // await NotificationService.clearAll();
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
          final syncRecord = await FileSyncService.syncFile(file, serverConfig, syncSessionId: syncSessionId);
          
          if (existingRecord != null) {
            await DatabaseService.updateSyncRecord(syncRecord);
          } else {
            await DatabaseService.insertSyncRecord(syncRecord);
          }

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

// StartSyncNow is now the main sync event for foreground/manual syncs.
// All UI and logic should treat this as the default sync action.
// If you want to rename StartSyncNow to StartSync for clarity, update the event and all references.
