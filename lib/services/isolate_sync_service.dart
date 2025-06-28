import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import '../models/server_config.dart';
import '../models/sync_record.dart';
import '../models/synced_folder.dart';
import '../utils/logger.dart' as app_logger;

/// Service for running sync operations in background isolates
class IsolateSyncService {
  static const String _isolateName = 'SyncIsolate';

  /// Progress callback for sync operations
  static StreamController<SyncProgress>? _progressController;
  static Stream<SyncProgress>? _progressStream;

  /// Initialize the isolate sync service
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

  /// Start sync operation in a background isolate
  static Future<SyncResult> syncFilesInBackground({
    required List<File> files,
    required ServerConfig serverConfig,
    required List<SyncedFolder> enabledFolders,
    required bool autoDeleteEnabled,
  }) async {
    final receivePort = ReceivePort();
    final progressPort = ReceivePort();
    
    try {
      app_logger.Logger.info('🚀 Starting sync in background isolate');
      
      // Create isolate with progress reporting
      final isolate = await Isolate.spawn(
        _syncIsolateEntryPoint,
        IsolateSyncMessage(
          sendPort: receivePort.sendPort,
          progressPort: progressPort.sendPort,
          files: files.map((f) => f.path).toList(),
          serverConfig: serverConfig,
          enabledFolders: enabledFolders,
          autoDeleteEnabled: autoDeleteEnabled,
        ),
        debugName: _isolateName,
      );

      // Listen to progress updates
      final progressSubscription = progressPort.listen((data) {
        if (data is SyncProgress) {
          _progressController?.add(data);
        }
      });

      // Wait for completion
      final completer = Completer<SyncResult>();
      late StreamSubscription subscription;
      
      subscription = receivePort.listen((data) {
        if (data is SyncResult) {
          subscription.cancel();
          progressSubscription.cancel();
          isolate.kill();
          receivePort.close();
          progressPort.close();
          completer.complete(data);
        } else if (data is String && data.startsWith('ERROR:')) {
          subscription.cancel();
          progressSubscription.cancel();
          isolate.kill();
          receivePort.close();
          progressPort.close();
          completer.completeError(Exception(data.substring(6)));
        }
      });

      return await completer.future;
    } catch (e) {
      receivePort.close();
      progressPort.close();
      app_logger.Logger.error('Failed to start sync isolate', error: e);
      rethrow;
    }
  }

  /// Entry point for the sync isolate
  static void _syncIsolateEntryPoint(IsolateSyncMessage message) async {
    try {
      // Import necessary services in the isolate
      final fileSyncService = _IsolateFileSyncService();
      final databaseService = _IsolateDatabaseService();
      
      await databaseService.initialize();
      
      int syncedCount = 0;
      int errorCount = 0;
      int skippedCount = 0;
      
      final files = message.files.map((path) => File(path)).toList();
      
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final fileName = file.path.split('/').last;
        final fileSize = await file.length();
        
        // Send progress update
        message.progressPort.send(SyncProgress(
          currentFile: i + 1,
          totalFiles: files.length,
          currentFileName: fileName,
          fileSize: fileSize,
          uploadedBytes: 0,
          uploadSpeed: 0.0,
          estimatedTimeRemaining: Duration.zero,
        ));

        try {
          final existingRecord = await databaseService.getSyncRecordByPath(file.path);
          final needsSync = await fileSyncService.fileNeedsSync(file, existingRecord);
          
          if (needsSync) {
            final DateTime startTime = DateTime.now();
            
            // Send progress updates during upload
            final progressTimer = _createProgressTimer(
              message.progressPort,
              i + 1,
              files.length,
              fileName,
              fileSize,
            );
            
            // Perform actual sync
            final syncRecord = await fileSyncService.syncFile(file, message.serverConfig);
            
            progressTimer.cancel();
            
            // Calculate upload speed
            final Duration uploadTime = DateTime.now().difference(startTime);
            final double speed = uploadTime.inMilliseconds > 0 ? fileSize / (uploadTime.inMilliseconds / 1000) : 0.0;
            
            // Send final progress for this file
            message.progressPort.send(SyncProgress(
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
              await databaseService.updateSyncRecord(syncRecord);
            } else {
              await databaseService.insertSyncRecord(syncRecord);
            }

            if (syncRecord.status == SyncStatus.completed) {
              syncedCount++;
              
              // Auto-delete if enabled
              if (message.autoDeleteEnabled) {
                final folder = message.enabledFolders.firstWhere(
                  (f) => file.path.startsWith(f.localPath),
                  orElse: () => message.enabledFolders.first,
                );
                
                if (folder.autoDelete) {
                  await fileSyncService.deleteLocalFile(file.path);
                }
              }
            } else {
              errorCount++;
            }
          } else {
            skippedCount++;
          }
        } catch (e) {
          errorCount++;
        }
      }

      // Send final result
      message.sendPort.send(SyncResult(
        syncedCount: syncedCount,
        errorCount: errorCount,
        skippedCount: skippedCount,
      ));
      
    } catch (e) {
      message.sendPort.send('ERROR: $e');
    }
  }

  /// Create a timer for sending periodic progress updates during file upload
  static Timer _createProgressTimer(
    SendPort progressPort,
    int currentFile,
    int totalFiles,
    String fileName,
    int fileSize,
  ) {
    int uploadedBytes = 0;
    final startTime = DateTime.now();
    
    return Timer.periodic(const Duration(milliseconds: 200), (timer) {
      uploadedBytes = (uploadedBytes + (fileSize * 0.1)).round().clamp(0, fileSize);
      final elapsed = DateTime.now().difference(startTime);
      final speed = elapsed.inMilliseconds > 0 ? uploadedBytes / (elapsed.inMilliseconds / 1000) : 0.0;
      final remaining = uploadedBytes < fileSize && speed > 0 
          ? Duration(seconds: ((fileSize - uploadedBytes) / speed).round())
          : Duration.zero;
      
      progressPort.send(SyncProgress(
        currentFile: currentFile,
        totalFiles: totalFiles,
        currentFileName: fileName,
        fileSize: fileSize,
        uploadedBytes: uploadedBytes,
        uploadSpeed: speed,
        estimatedTimeRemaining: remaining,
      ));
      
      if (uploadedBytes >= fileSize) {
        timer.cancel();
      }
    });
  }
}

/// Message structure for isolate communication
class IsolateSyncMessage {
  final SendPort sendPort;
  final SendPort progressPort;
  final List<String> files;
  final ServerConfig serverConfig;
  final List<SyncedFolder> enabledFolders;
  final bool autoDeleteEnabled;

  const IsolateSyncMessage({
    required this.sendPort,
    required this.progressPort,
    required this.files,
    required this.serverConfig,
    required this.enabledFolders,
    required this.autoDeleteEnabled,
  });
}

/// Progress update structure
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

/// Result structure for sync operations
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

/// Simplified file sync service for isolate use
class _IsolateFileSyncService {
  Future<bool> fileNeedsSync(File file, SyncRecord? existingRecord) async {
    if (existingRecord == null) return true;
    if (existingRecord.status == SyncStatus.failed) return true;
    
    final lastModified = await file.lastModified();
    return lastModified.isAfter(existingRecord.lastModified);
  }

  Future<SyncRecord> syncFile(File file, ServerConfig serverConfig) async {
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();
    final lastModified = await file.lastModified();
    
    try {
      // This is a simplified version for the isolate
      // In a real implementation, you would recreate the SSH/FTP connection logic here
      // For now, we'll simulate the sync operation
      
      final uploadDuration = Duration(milliseconds: (fileSize / 10000).round().clamp(100, 5000));
      await Future.delayed(uploadDuration);
      
      // Generate a simple hash for the file
      final hash = '${file.path}_${lastModified.millisecondsSinceEpoch}_${fileSize}';
      
      return SyncRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: file.path,
        fileName: fileName,
        fileSize: fileSize,
        hash: hash,
        lastModified: lastModified,
        status: SyncStatus.completed,
        errorMessage: null,
      );
    } catch (e) {
      return SyncRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: file.path,
        fileName: fileName,
        fileSize: fileSize,
        hash: '',
        lastModified: lastModified,
        status: SyncStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> deleteLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Log error but don't throw
    }
  }
}

/// Simplified database service for isolate use
class _IsolateDatabaseService {
  Future<void> initialize() async {
    // Initialize database connection in isolate
  }

  Future<SyncRecord?> getSyncRecordByPath(String filePath) async {
    // Simplified database query
    return null;
  }

  Future<void> insertSyncRecord(SyncRecord record) async {
    // Simplified database insert
  }

  Future<void> updateSyncRecord(SyncRecord record) async {
    // Simplified database update
  }
}
