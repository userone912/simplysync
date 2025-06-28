import 'package:equatable/equatable.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../models/synced_folder.dart';
import '../models/sync_record.dart';

abstract class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => [];
}

class SyncInitial extends SyncState {}

class SyncLoading extends SyncState {}

class SyncLoaded extends SyncState {
  final ServerConfig? serverConfig;
  final SchedulerConfig schedulerConfig;
  final List<SyncedFolder> syncedFolders;
  final List<SyncRecord> syncHistory;
  final List<SyncRecord> recentActivityRecords;
  final bool autoDeleteEnabled;
  final bool permissionsGranted;

  const SyncLoaded({
    this.serverConfig,
    required this.schedulerConfig,
    required this.syncedFolders,
    required this.syncHistory,
    required this.recentActivityRecords,
    required this.autoDeleteEnabled,
    required this.permissionsGranted,
  });

  SyncLoaded copyWith({
    ServerConfig? serverConfig,
    SchedulerConfig? schedulerConfig,
    List<SyncedFolder>? syncedFolders,
    List<SyncRecord>? syncHistory,
    List<SyncRecord>? recentActivityRecords,
    bool? autoDeleteEnabled,
    bool? permissionsGranted,
  }) {
    return SyncLoaded(
      serverConfig: serverConfig ?? this.serverConfig,
      schedulerConfig: schedulerConfig ?? this.schedulerConfig,
      syncedFolders: syncedFolders ?? this.syncedFolders,
      syncHistory: syncHistory ?? this.syncHistory,
      recentActivityRecords: recentActivityRecords ?? this.recentActivityRecords,
      autoDeleteEnabled: autoDeleteEnabled ?? this.autoDeleteEnabled,
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
    );
  }

  @override
  List<Object?> get props => [
        serverConfig,
        schedulerConfig,
        syncedFolders,
        syncHistory,
        recentActivityRecords,
        autoDeleteEnabled,
        permissionsGranted,
      ];
}

class SyncInProgress extends SyncState {
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;
  final int fileSize;
  final int uploadedBytes;
  final double uploadSpeed; // bytes per second
  final Duration estimatedTimeRemaining;
  // Statistics for UI display during sync
  final List<SyncedFolder> syncedFolders;
  final List<SyncRecord> syncHistory;
  final List<SyncRecord> recentActivityRecords;

  const SyncInProgress({
    required this.currentFile,
    required this.totalFiles,
    this.currentFileName,
    this.fileSize = 0,
    this.uploadedBytes = 0,
    this.uploadSpeed = 0.0,
    this.estimatedTimeRemaining = Duration.zero,
    this.syncedFolders = const [],
    this.syncHistory = const [],
    this.recentActivityRecords = const [],
  });

  double get fileProgress => fileSize > 0 ? uploadedBytes / fileSize : 0.0;
  double get overallProgress => totalFiles > 0 ? currentFile / totalFiles : 0.0;

  @override
  List<Object?> get props => [
    currentFile, 
    totalFiles, 
    currentFileName, 
    fileSize, 
    uploadedBytes, 
    uploadSpeed, 
    estimatedTimeRemaining,
    syncedFolders,
    syncHistory,
    recentActivityRecords,
  ];
}

class SyncSuccess extends SyncState {
  final int syncedCount;
  final int errorCount;

  const SyncSuccess({
    required this.syncedCount,
    required this.errorCount,
  });

  @override
  List<Object> get props => [syncedCount, errorCount];
}

class SyncError extends SyncState {
  final String message;

  const SyncError(this.message);

  @override
  List<Object> get props => [message];
}

class ConnectionTesting extends SyncState {}

class ConnectionTestSuccess extends SyncState {}

class ConnectionTestFailure extends SyncState {
  final String message;

  const ConnectionTestFailure(this.message);

  @override
  List<Object> get props => [message];
}

class PermissionRequired extends SyncState {
  final List<String> missingPermissions;

  const PermissionRequired(this.missingPermissions);

  @override
  List<Object> get props => [missingPermissions];
}
