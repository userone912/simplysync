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
  final bool autoDeleteEnabled;
  final bool permissionsGranted;

  const SyncLoaded({
    this.serverConfig,
    required this.schedulerConfig,
    required this.syncedFolders,
    required this.syncHistory,
    required this.autoDeleteEnabled,
    required this.permissionsGranted,
  });

  SyncLoaded copyWith({
    ServerConfig? serverConfig,
    SchedulerConfig? schedulerConfig,
    List<SyncedFolder>? syncedFolders,
    List<SyncRecord>? syncHistory,
    bool? autoDeleteEnabled,
    bool? permissionsGranted,
  }) {
    return SyncLoaded(
      serverConfig: serverConfig ?? this.serverConfig,
      schedulerConfig: schedulerConfig ?? this.schedulerConfig,
      syncedFolders: syncedFolders ?? this.syncedFolders,
      syncHistory: syncHistory ?? this.syncHistory,
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
        autoDeleteEnabled,
        permissionsGranted,
      ];
}

class SyncInProgress extends SyncState {
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;

  const SyncInProgress({
    required this.currentFile,
    required this.totalFiles,
    this.currentFileName,
  });

  @override
  List<Object?> get props => [currentFile, totalFiles, currentFileName];
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
