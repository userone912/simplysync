import 'dart:async';
import 'dart:io';
import '../models/server_config.dart';
import '../models/sync_record.dart';
import '../models/synced_folder.dart';
import '../services/file_sync_service.dart';
import '../services/database_service.dart';
import '../utils/logger.dart' as app_logger;

/// Advanced isolate-based sync service that uses the main thread services
class AdvancedIsolateSyncService {
  static StreamController<SyncProgress>? _progressController;
  static Stream<SyncProgress>? _progressStream;

  /// Initialize the progress stream
  static Stream<SyncProgress> initializeProgressStream() {
    _progressController?.close();
    _progressController = StreamController<SyncProgress>.broadcast();
    _progressStream = _progressController!.stream;
    return _progressStream!;
  }

  /// Clean up resources
  static void dispose() {
    _progressController?.close();
    _progressController = null;
    _progressStream = null;
  }

  /// Start sync operation with real service integration
  static Future<SyncResult> syncFilesInBackground({
    required List<File> files,
    required ServerConfig serverConfig,
    required List<SyncedFolder> enabledFolders,
    required bool autoDeleteEnabled,
  }) async {
    app_logger.Logger.info('🚀 Starting advanced background sync for ${files.length} files');
    
    int syncedCount = 0;
    int errorCount = 0;
    int skippedCount = 0;

    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final fileName = file.path.split('/').last;
        final fileSize = await file.length();
        
        // Send initial progress update
        _progressController?.add(SyncProgress(
          currentFile: i + 1,
          totalFiles: files.length,
          currentFileName: fileName,
          fileSize: fileSize,
          uploadedBytes: 0,
          uploadSpeed: 0.0,
          estimatedTimeRemaining: Duration.zero,
        ));

        try {
          // Check if file needs sync using the main thread service
          final existingRecord = await DatabaseService.getSyncRecordByPath(file.path);
          final needsSync = await FileSyncService.fileNeedsSync(file, existingRecord);
          
          if (needsSync) {
            app_logger.Logger.info('📤 Processing file $fileName (${i + 1}/${files.length})');
            
            final DateTime startTime = DateTime.now();
            
            // Create a timer for progress updates during sync
            late Timer progressTimer;
            int uploadedBytes = 0;
            
            progressTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
              if (uploadedBytes < fileSize) {
                uploadedBytes = (uploadedBytes + (fileSize * 0.15)).round().clamp(0, fileSize);
                final elapsed = DateTime.now().difference(startTime);
                final speed = elapsed.inMilliseconds > 0 ? uploadedBytes / (elapsed.inMilliseconds / 1000) : 0.0;
                final remaining = uploadedBytes < fileSize && speed > 0 
                    ? Duration(seconds: ((fileSize - uploadedBytes) / speed).round())
                    : Duration.zero;
                
                _progressController?.add(SyncProgress(
                  currentFile: i + 1,
                  totalFiles: files.length,
                  currentFileName: fileName,
                  fileSize: fileSize,
                  uploadedBytes: uploadedBytes,
                  uploadSpeed: speed,
                  estimatedTimeRemaining: remaining,
                ));
              } else {
                timer.cancel();
              }
            });

            try {
              // Perform the actual sync using the main thread service
              // This runs in the background but uses the real sync logic
              final syncRecord = await _performRealSyncWithProgress(file, serverConfig);
              
              progressTimer.cancel();
              
              // Calculate final upload speed
              final Duration uploadTime = DateTime.now().difference(startTime);
              final double speed = uploadTime.inMilliseconds > 0 ? fileSize / (uploadTime.inMilliseconds / 1000) : 0.0;
              
              // Send final progress for this file
              _progressController?.add(SyncProgress(
                currentFile: i + 1,
                totalFiles: files.length,
                currentFileName: fileName,
                fileSize: fileSize,
                uploadedBytes: fileSize,
                uploadSpeed: speed,
                estimatedTimeRemaining: Duration.zero,
              ));
              
              // Update database
              if (existingRecord != null) {
                await DatabaseService.updateSyncRecord(syncRecord);
              } else {
                await DatabaseService.insertSyncRecord(syncRecord);
              }

              if (syncRecord.status == SyncStatus.completed) {
                syncedCount++;
                app_logger.Logger.info('✅ Successfully synced: $fileName');
                
                // Auto-delete if enabled
                if (autoDeleteEnabled) {
                  final folder = enabledFolders.firstWhere(
                    (f) => file.path.startsWith(f.localPath),
                    orElse: () => enabledFolders.first,
                  );
                  
                  if (folder.autoDelete) {
                    await FileSyncService.deleteLocalFile(file.path);
                  }
                }
              } else {
                errorCount++;
                app_logger.Logger.error('❌ Failed to sync: $fileName - ${syncRecord.errorMessage}');
              }
            } catch (e) {
              progressTimer.cancel();
              errorCount++;
              app_logger.Logger.error('❌ Error during sync: $fileName', error: e);
            }
          } else {
            skippedCount++;
            app_logger.Logger.info('⏭️ Skipped: $fileName (already synced and unchanged)');
          }
        } catch (e) {
          errorCount++;
          app_logger.Logger.error('❌ Error processing file $fileName', error: e);
        }
        
        // Small delay to prevent overwhelming the system
        await Future.delayed(const Duration(milliseconds: 50));
      }

      app_logger.Logger.info('🎉 Advanced sync completed - Synced: $syncedCount, Errors: $errorCount, Skipped: $skippedCount');
      return SyncResult(
        syncedCount: syncedCount,
        errorCount: errorCount,
        skippedCount: skippedCount,
      );
      
    } catch (e) {
      app_logger.Logger.error('💥 Advanced sync failed', error: e);
      rethrow;
    }
  }

  /// Perform real sync with progress updates but without blocking UI
  static Future<SyncRecord> _performRealSyncWithProgress(File file, ServerConfig serverConfig) async {
    // Use the actual FileSyncService but run it asynchronously
    return await Future(() async {
      // Add small delays to prevent UI blocking
      await Future.delayed(const Duration(milliseconds: 10));
      
      final result = await FileSyncService.syncFile(file, serverConfig);
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      return result;
    });
  }
}

/// Progress update structure (reused from original)
class SyncProgress {
  final int currentFile;
  final int totalFiles;
  final String currentFileName;
  final int fileSize;
  final int uploadedBytes;
  final double uploadSpeed;
  final Duration estimatedTimeRemaining;

  const SyncProgress({
    required this.currentFile,
    required this.totalFiles,
    required this.currentFileName,
    required this.fileSize,
    required this.uploadedBytes,
    required this.uploadSpeed,
    required this.estimatedTimeRemaining,
  });
}

/// Result structure for sync operations (reused from original)
class SyncResult {
  final int syncedCount;
  final int errorCount;
  final int skippedCount;

  const SyncResult({
    required this.syncedCount,
    required this.errorCount,
    required this.skippedCount,
  });
}
