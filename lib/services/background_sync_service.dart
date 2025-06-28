import 'package:workmanager/workmanager.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/file_scanner_service.dart';
import '../services/file_sync_service.dart';
import '../utils/logger.dart' as app_logger;

class BackgroundSyncService {
  static const String syncTaskName = 'sync_files_task';
  static const String syncTaskTag = 'file_sync';

  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );
    
    // Initialize notification service for background tasks
    // await NotificationService.initialize();
    app_logger.Logger.info('🔄 Background sync service initialized');
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
    await Workmanager().cancelByTag(syncTaskTag);
    // await NotificationService.clearAll();
    app_logger.Logger.info('⏹️ Background sync cancelled');
  }

  static Future<void> runSyncNow() async {
    await Workmanager().registerOneOffTask(
      'sync_now_${DateTime.now().millisecondsSinceEpoch}',
      syncTaskName,
      tag: 'sync_now',
    );
  }

  static Future<bool> performSync() async {
    try {
      app_logger.Logger.info('🚀 Background sync started');
      // await NotificationService.showSyncStarted();
      
      // Get settings
      final serverConfig = await SettingsService.getServerConfig();
      if (serverConfig == null) {
        app_logger.Logger.error('No server configuration found');
        // await NotificationService.showSyncFailed('No server configuration');
        return false;
      }

      // Get enabled folders
      final folders = await DatabaseService.getEnabledSyncedFolders();
      if (folders.isEmpty) {
        app_logger.Logger.info('No enabled folders found');
        // await NotificationService.clearSyncProgress();
        return true; // Not an error
      }

      // Test connection
      final connectionOk = await FileSyncService.testConnection(serverConfig);
      if (!connectionOk) {
        app_logger.Logger.error('Connection test failed');
        // await NotificationService.showSyncFailed('Connection failed');
        return false;
      }

      // Scan for files
      final files = await FileScannerService.scanFoldersForFiles(folders);
      app_logger.Logger.info('Found ${files.length} files to check');

      if (files.isEmpty) {
        // await NotificationService.showSyncCompleted(syncedCount: 0, errorCount: 0);
        return true;
      }

      int syncedCount = 0;
      int errorCount = 0;

      // Process each file with progress notifications
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final fileName = file.path.split('/').last;
        
        // await NotificationService.showSyncProgress(
        //   currentFile: i + 1,
        //   totalFiles: files.length,
        //   fileName: fileName,
        // );

        try {
          // Check if file needs sync
          final existingRecord = await DatabaseService.getSyncRecordByPath(file.path);
          final needsSync = await FileSyncService.fileNeedsSync(file, existingRecord);
          
          if (!needsSync) continue;

          app_logger.Logger.info('Syncing file: $fileName (${i + 1}/${files.length})');

          // Sync the file
          final syncRecord = await FileSyncService.syncFile(file, serverConfig);
          
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
      // await NotificationService.showSyncCompleted(syncedCount: syncedCount, errorCount: errorCount);
      
      return errorCount == 0;
    } catch (e) {
      app_logger.Logger.error('Background sync failed', error: e);
      // await NotificationService.showSyncFailed(e.toString());
      return false;
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
