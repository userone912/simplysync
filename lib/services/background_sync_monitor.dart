import 'dart:async';
import '../services/database_service.dart';
import '../services/background_sync_service.dart';
import '../models/sync_record.dart';
import '../utils/logger.dart' as app_logger;

class BackgroundSyncMonitor {
  static Timer? _monitorTimer;
  static StreamController<BackgroundSyncStatus>? _statusController;
  static BackgroundSyncStatus? _lastStatus;
  static DateTime? _lastActiveTime;
  
  static Stream<BackgroundSyncStatus> get statusStream {
    _statusController ??= StreamController<BackgroundSyncStatus>.broadcast();
    return _statusController!.stream;
  }
  
  static void startMonitoring() {
    if (_monitorTimer != null) return;
    
    app_logger.Logger.info('📊 Starting background sync monitoring');
    
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final status = await _checkSyncStatus();
        if (status != _lastStatus) {
          _lastStatus = status;
          _statusController?.add(status);
        }
      } catch (e) {
        app_logger.Logger.error('Error monitoring sync status', error: e);
      }
    });
  }
  
  static void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    app_logger.Logger.info('📊 Stopped background sync monitoring');
  }
  
  static Future<BackgroundSyncStatus> _checkSyncStatus() async {
    try {
      // Check the sync status from BackgroundSyncService first
      final status = await BackgroundSyncService.getSyncStatus();
      final progress = await BackgroundSyncService.getSyncProgress();
      
      if (status == 'syncing' && progress != null) {
        _lastActiveTime = DateTime.now();
        return BackgroundSyncStatus.inProgress(
          currentFile: (progress['currentFile'] as int?) ?? 1,
          totalFiles: (progress['totalFiles'] as int?) ?? 1,
          currentFileName: progress['fileName'] as String?,
          syncedCount: (progress['syncedCount'] as int?) ?? 0,
          errorCount: (progress['errorCount'] as int?) ?? 0,
          fileSize: (progress['fileSize'] as int?) ?? 0,
          uploadedBytes: (progress['uploadedBytes'] as int?) ?? 0,
          uploadSpeed: (progress['uploadSpeed'] as double?) ?? 0.0,
        );
      } else if (status == 'starting') {
        _lastActiveTime = DateTime.now();
        return BackgroundSyncStatus.inProgress(
          currentFile: 0,
          totalFiles: 1,
          currentFileName: 'Preparing sync...',
          syncedCount: 0,
          errorCount: 0,
        );
      }
      
      // If we were recently active (within last 3 seconds), maintain sync state to prevent glitching
      if (_lastActiveTime != null && 
          DateTime.now().difference(_lastActiveTime!).inSeconds < 3 &&
          _lastStatus?.isActive == true) {
        // Return the last active status to prevent UI glitching
        return _lastStatus!;
      }
      
      // If status is idle but we have recent progress, check if sync is truly complete
      if (status == 'idle' && progress != null) {
        final totalFiles = (progress['totalFiles'] as int?) ?? 0;
        final syncedCount = (progress['syncedCount'] as int?) ?? 0;
        final errorCount = (progress['errorCount'] as int?) ?? 0;
        final totalProcessed = syncedCount + errorCount;
        
        if (progress['completed'] == true || (totalFiles > 0 && totalProcessed >= totalFiles)) {
          // Sync is truly completed - show completion state briefly then go idle
          if (_lastStatus?.isActive == true) {
            // First time detecting completion, show completion state
            return BackgroundSyncStatus.inProgress(
              currentFile: totalFiles,
              totalFiles: totalFiles,
              currentFileName: 'Sync completed',
              syncedCount: syncedCount,
              errorCount: errorCount,
            );
          } else {
            // Already showed completion, now go idle
            return BackgroundSyncStatus.idle();
          }
        } else if (totalFiles > 0 && totalProcessed < totalFiles) {
          // Sync not yet complete, continue showing progress
          return BackgroundSyncStatus.inProgress(
            currentFile: totalProcessed + 1,
            totalFiles: totalFiles,
            currentFileName: progress['fileName'] as String? ?? 'Processing...',
            syncedCount: syncedCount,
            errorCount: errorCount,
          );
        }
      }
      
      // Fall back to checking recent database activity for better continuity
      final recentRecords = await DatabaseService.getRecentSyncRecords(const Duration(minutes: 1));
      
      if (recentRecords.isNotEmpty) {
        // Check if there's been very recent activity (last 30 seconds)
        final veryRecentRecords = await DatabaseService.getRecentSyncRecords(const Duration(seconds: 30));
        
        if (veryRecentRecords.isNotEmpty || _lastStatus?.isActive == true) {
          // Continue showing sync state if we were recently syncing
          final completedFiles = recentRecords.where((r) => r.status == SyncStatus.completed).length;
          final errorFiles = recentRecords.where((r) => r.status == SyncStatus.failed).length;
          final currentFile = recentRecords.first;
          
          return BackgroundSyncStatus.inProgress(
            currentFile: completedFiles + errorFiles + 1,
            totalFiles: recentRecords.length > 0 ? recentRecords.length : 1,
            currentFileName: currentFile.fileName,
            syncedCount: completedFiles,
            errorCount: errorFiles,
          );
        }
      }
      
      return BackgroundSyncStatus.idle();
    } catch (e) {
      app_logger.Logger.error('Error checking sync status', error: e);
      return BackgroundSyncStatus.idle();
    }
  }
  
  static void dispose() {
    stopMonitoring();
    _statusController?.close();
    _statusController = null;
    _lastStatus = null;
  }
}

class BackgroundSyncStatus {
  final bool isActive;
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;
  final int syncedCount;
  final int errorCount;
  final int fileSize;
  final int uploadedBytes;
  final double uploadSpeed;
  
  const BackgroundSyncStatus._({
    required this.isActive,
    this.currentFile = 0,
    this.totalFiles = 0,
    this.currentFileName,
    this.syncedCount = 0,
    this.errorCount = 0,
    this.fileSize = 0,
    this.uploadedBytes = 0,
    this.uploadSpeed = 0.0,
  });
  
  factory BackgroundSyncStatus.idle() {
    return const BackgroundSyncStatus._(isActive: false);
  }
  
  factory BackgroundSyncStatus.inProgress({
    required int currentFile,
    required int totalFiles,
    String? currentFileName,
    int syncedCount = 0,
    int errorCount = 0,
    int fileSize = 0,
    int uploadedBytes = 0,
    double uploadSpeed = 0.0,
  }) {
    return BackgroundSyncStatus._(
      isActive: true,
      currentFile: currentFile,
      totalFiles: totalFiles,
      currentFileName: currentFileName,
      syncedCount: syncedCount,
      errorCount: errorCount,
      fileSize: fileSize,
      uploadedBytes: uploadedBytes,
      uploadSpeed: uploadSpeed,
    );
  }
  
  double get progress => totalFiles > 0 ? currentFile / totalFiles : 0.0;
  double get fileProgress => fileSize > 0 ? uploadedBytes / fileSize : 0.0;
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BackgroundSyncStatus) return false;
    return isActive == other.isActive &&
           currentFile == other.currentFile &&
           totalFiles == other.totalFiles &&
           currentFileName == other.currentFileName &&
           syncedCount == other.syncedCount &&
           errorCount == other.errorCount &&
           fileSize == other.fileSize &&
           uploadedBytes == other.uploadedBytes &&
           uploadSpeed == other.uploadSpeed;
  }
  
  @override
  int get hashCode {
    return Object.hash(isActive, currentFile, totalFiles, currentFileName, 
                      syncedCount, errorCount, fileSize, uploadedBytes, uploadSpeed);
  }
}
