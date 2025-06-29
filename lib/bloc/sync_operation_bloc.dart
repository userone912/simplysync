import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/sync_record.dart';
import '../services/database_service.dart';
import '../services/background_sync_service.dart';
import '../services/background_sync_monitor.dart';
import '../utils/logger.dart' as app_logger;

// Events
abstract class SyncOperationEvent extends Equatable {
  const SyncOperationEvent();
  @override
  List<Object?> get props => [];
}

class StartSync extends SyncOperationEvent {}

class StartSyncNow extends SyncOperationEvent {}

class LoadSyncHistory extends SyncOperationEvent {}

class UpdateBackgroundSyncProgress extends SyncOperationEvent {
  final BackgroundSyncStatus status;
  const UpdateBackgroundSyncProgress(this.status);
  @override
  List<Object> get props => [status];
}

class SwitchToBackgroundSync extends SyncOperationEvent {}

class PauseSync extends SyncOperationEvent {}

class ResumeSync extends SyncOperationEvent {}

// States
abstract class SyncOperationState extends Equatable {
  const SyncOperationState();
  @override
  List<Object?> get props => [];
}

class SyncOperationInitial extends SyncOperationState {}

class SyncOperationLoaded extends SyncOperationState {
  final List<SyncRecord> syncHistory;
  final List<SyncRecord> recentActivityRecords;
  
  const SyncOperationLoaded({
    required this.syncHistory,
    required this.recentActivityRecords,
  });
  
  @override
  List<Object> get props => [syncHistory, recentActivityRecords];
}

class SyncInProgress extends SyncOperationState {
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;
  final int fileSize;
  final int uploadedBytes;
  final double uploadSpeed;
  final Duration estimatedTimeRemaining;

  const SyncInProgress({
    required this.currentFile,
    required this.totalFiles,
    this.currentFileName,
    this.fileSize = 0,
    this.uploadedBytes = 0,
    this.uploadSpeed = 0.0,
    this.estimatedTimeRemaining = Duration.zero,
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
  ];
}

class SyncSuccess extends SyncOperationState {
  final int syncedCount;
  final int errorCount;

  const SyncSuccess({
    required this.syncedCount,
    required this.errorCount,
  });

  @override
  List<Object> get props => [syncedCount, errorCount];
}

class SyncError extends SyncOperationState {
  final String message;
  const SyncError(this.message);
  @override
  List<Object> get props => [message];
}

class SyncPaused extends SyncOperationState {
  final double progress;
  final int currentFile;
  final int totalFiles;
  final String? currentFileName;

  SyncPaused({
    required this.progress,
    required this.currentFile,
    required this.totalFiles,
    this.currentFileName,
  });
}

// BLoC
class SyncOperationBloc extends Bloc<SyncOperationEvent, SyncOperationState> {
  StreamSubscription<BackgroundSyncStatus>? _backgroundSyncSubscription;
  Timer? _progressPollingTimer;
  String? _currentSessionId;

  SyncOperationBloc() : super(SyncOperationInitial()) {
    on<StartSync>(_onStartSync);
    on<StartSyncNow>(_onStartSyncNow);
    on<LoadSyncHistory>(_onLoadSyncHistory);
    on<UpdateBackgroundSyncProgress>(_onUpdateBackgroundSyncProgress);
    on<SwitchToBackgroundSync>(_onSwitchToBackgroundSync);
    on<PauseSync>((event, emit) async {
      app_logger.Logger.info('⏸ Pausing sync');
      _progressPollingTimer?.cancel();
      // Actually cancel/pause the background sync job
      try {
        await BackgroundSyncService.cancelSync();
        app_logger.Logger.info('Background sync cancelled successfully');
      } catch (e) {
        app_logger.Logger.error('Failed to cancel background sync', error: e);
      }
      if (state is SyncInProgress) {
        final inProgress = state as SyncInProgress;
        emit(SyncPaused(
          progress: inProgress.overallProgress,
          currentFile: inProgress.currentFile,
          totalFiles: inProgress.totalFiles,
          currentFileName: inProgress.currentFileName,
        ));
      } else {
        // If not in progress, just reload history
        add(LoadSyncHistory());
      }
    });
    
    on<ResumeSync>((event, emit) async {
      app_logger.Logger.info('▶️ Resuming sync');
      // Optionally, you can restore progress from SyncPaused state
      if (state is SyncPaused) {
        // You may want to pass progress info to your sync service
        await BackgroundSyncService.resumeSync();
        // Optionally, emit SyncInProgress or trigger StartSync
        add(StartSync());
      } else {
        // If not paused, just start sync
        add(StartSync());
      }
    });

    _startBackgroundSyncMonitoring();
  }

  void _startBackgroundSyncMonitoring() {
    BackgroundSyncMonitor.startMonitoring();
    _backgroundSyncSubscription = BackgroundSyncMonitor.statusStream.listen((status) {
      add(UpdateBackgroundSyncProgress(status));
    });
  }

  Future<void> _onStartSync(StartSync event, Emitter<SyncOperationState> emit) async {
    try {
      app_logger.Logger.info('🚀 Starting background sync');
      await BackgroundSyncService.runSyncNow();
      
      // Load sync history to show updated state
      add(LoadSyncHistory());
    } catch (e) {
      app_logger.Logger.error('Failed to start background sync', error: e);
      emit(SyncError('Failed to start sync: $e'));
      add(LoadSyncHistory()); // Return to loaded state
    }
  }

  Future<void> _onStartSyncNow(StartSyncNow event, Emitter<SyncOperationState> emit) async {
    try {
      app_logger.Logger.info('🐞 Starting sync Now');
      emit(SyncInProgress(
        currentFile: 0,
        totalFiles: 0,
        currentFileName: null,
      ));
      // Call the sync logic directly (not via WorkManager)
      final success = await BackgroundSyncService.performSync();
      if (success) {
        emit(SyncSuccess(syncedCount: 0, errorCount: 0));
      } else {
        emit(SyncError('Error : Sync canceled'));
      }
      add(LoadSyncHistory());
    } catch (e) {
      app_logger.Logger.error('Sync canceled', error: e);
      emit(SyncError('Sync canceled: $e'));
      add(LoadSyncHistory());
    }
  }

  Future<void> _onLoadSyncHistory(LoadSyncHistory event, Emitter<SyncOperationState> emit) async {
    try {
      final syncHistory = await DatabaseService.getAllSyncRecords();
      final recentActivityRecords = await DatabaseService.getLatestSyncSessionRecords();
      emit(SyncOperationLoaded(
        syncHistory: syncHistory,
        recentActivityRecords: recentActivityRecords,
      ));
    } catch (e) {
      emit(SyncError('Failed to load sync history: $e'));
    }
  }

  void _startProgressPolling(String syncSessionId, Emitter<SyncOperationState> emit) {
    _progressPollingTimer?.cancel();
    int lastCompleted = -1;
    _progressPollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final progress = await DatabaseService.getSyncProgressBySession(syncSessionId);
      final total = progress['total'] ?? 0;
      final completed = progress['completed'] ?? 0;
      final inProgress = progress['inProgress'] ?? 0;
      final failed = progress['failed'] ?? 0;
      // For UI: currentFile = completed + inProgress + failed
      if (!emit.isDone) {
        emit(SyncInProgress(
          currentFile: completed + inProgress + failed,
          totalFiles: total,
          currentFileName: null, // Optionally fetch current file name if needed
        ));
      }
      // Emit SyncOperationLoaded if a new file has completed
      if (completed > lastCompleted) {
        lastCompleted = completed;
        final syncHistory = await DatabaseService.getAllSyncRecords();
        final recentActivityRecords = await DatabaseService.getLatestSyncSessionRecords();
        if (!emit.isDone) {
          emit(SyncOperationLoaded(
            syncHistory: syncHistory,
            recentActivityRecords: recentActivityRecords,
          ));
        }
      }
      // Stop polling if done
      if (completed + failed >= total && total > 0) {
        if (!emit.isDone) {
          emit(SyncSuccess(syncedCount: completed, errorCount: failed));
        }
        add(LoadSyncHistory());
        _progressPollingTimer?.cancel();
      }
    });
  }

  Future<void> _onUpdateBackgroundSyncProgress(UpdateBackgroundSyncProgress event, Emitter<SyncOperationState> emit) async {
    final status = event.status;
    if (status.isActive) {
      // Try to get syncSessionId from status, else fetch from DB
      String? sessionId;
      try {
        // Try to access syncSessionId if it exists
        sessionId = (status as dynamic).syncSessionId as String?;
      } catch (_) {
        // Fallback: fetch latest sessionId from DB
        sessionId = await DatabaseService.getLatestSyncSessionId();
      }
      if (sessionId != null && sessionId != _currentSessionId) {
        _currentSessionId = sessionId;
        _startProgressPolling(sessionId, emit);
      }
      // Optionally emit immediate state for UI responsiveness
      emit(SyncInProgress(
        currentFile: status.currentFile,
        totalFiles: status.totalFiles,
        currentFileName: status.currentFileName,
        fileSize: status.fileSize,
        uploadedBytes: status.uploadedBytes,
        uploadSpeed: status.uploadSpeed,
        estimatedTimeRemaining: status.uploadSpeed > 0 && status.fileSize > status.uploadedBytes
          ? Duration(seconds: ((status.fileSize - status.uploadedBytes) / status.uploadSpeed).round())
          : Duration.zero,
      ));
    } else if (!status.isActive && state is SyncInProgress) {
      _progressPollingTimer?.cancel();
      final inProgressState = state as SyncInProgress;
      final totalProcessed = status.syncedCount + status.errorCount;
      if (totalProcessed >= inProgressState.totalFiles && inProgressState.totalFiles > 0) {
        emit(SyncSuccess(
          syncedCount: status.syncedCount,
          errorCount: status.errorCount,
        ));
        add(LoadSyncHistory());
      }
    }
  }

  Future<void> _onSwitchToBackgroundSync(SwitchToBackgroundSync event, Emitter<SyncOperationState> emit) async {
    app_logger.Logger.info('App switched to background - background sync continues');
    
    if (state is! SyncOperationLoaded) {
      add(LoadSyncHistory());
    }
  }
  
  @override
  Future<void> close() {
    _backgroundSyncSubscription?.cancel();
    _progressPollingTimer?.cancel();
    BackgroundSyncMonitor.stopMonitoring();
    return super.close();
  }
}
