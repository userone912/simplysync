import 'package:workmanager/workmanager.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/file_scanner_service.dart';
import '../services/file_sync_service.dart';

class BackgroundSyncService {
  static const String syncTaskName = 'sync_files_task';
  static const String syncTaskTag = 'file_sync';

  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );
  }

  static Future<void> scheduleSync(SchedulerConfig config) async {
    if (!config.enabled) {
      await cancelSync();
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
  }

  static Future<void> cancelSync() async {
    await Workmanager().cancelByTag(syncTaskTag);
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
      print('Background sync started');
      
      // Get settings
      final serverConfig = await SettingsService.getServerConfig();
      if (serverConfig == null) {
        print('No server configuration found');
        return false;
      }

      // Get enabled folders
      final folders = await DatabaseService.getEnabledSyncedFolders();
      if (folders.isEmpty) {
        print('No enabled folders found');
        return true; // Not an error
      }

      // Test connection
      final connectionOk = await FileSyncService.testConnection(serverConfig);
      if (!connectionOk) {
        print('Connection test failed');
        return false;
      }

      // Scan for files
      final files = await FileScannerService.scanFoldersForFiles(folders);
      print('Found ${files.length} files to check');

      int syncedCount = 0;
      int errorCount = 0;

      // Process each file
      for (final file in files) {
        try {
          // Check if file needs sync
          final existingRecord = await DatabaseService.getSyncRecordByPath(file.path);
          final needsSync = await FileSyncService.fileNeedsSync(file, existingRecord);
          
          if (!needsSync) continue;

          // Sync the file
          final syncRecord = await FileSyncService.syncFile(file, serverConfig);
          
          if (existingRecord != null) {
            await DatabaseService.updateSyncRecord(syncRecord);
          } else {
            await DatabaseService.insertSyncRecord(syncRecord);
          }

          if (syncRecord.status == SyncStatus.completed) {
            syncedCount++;
            
            // Auto-delete if enabled
            final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
            if (autoDeleteEnabled) {
              final folder = folders.firstWhere(
                (f) => file.path.startsWith(f.localPath),
                orElse: () => folders.first,
              );
              
              if (folder.autoDelete) {
                await FileSyncService.deleteLocalFile(file.path);
                print('Auto-deleted: ${file.path}');
              }
            }
          } else {
            errorCount++;
          }
        } catch (e) {
          print('Error processing file ${file.path}: $e');
          errorCount++;
        }
      }

      print('Background sync completed: $syncedCount synced, $errorCount errors');
      return errorCount == 0;
    } catch (e) {
      print('Background sync failed: $e');
      return false;
    }
  }
}

// Top-level function for Workmanager callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('Background task started: $task');
    
    try {
      switch (task) {
        case BackgroundSyncService.syncTaskName:
        case 'sync_now':
          final success = await BackgroundSyncService.performSync();
          return success;
        default:
          print('Unknown task: $task');
          return false;
      }
    } catch (e) {
      print('Background task error: $e');
      return false;
    }
  });
}
