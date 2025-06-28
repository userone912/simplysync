import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/synced_folder.dart';
import '../models/server_config.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import '../services/file_sync_service.dart';
import '../services/background_sync_service.dart';
import '../services/background_sync_monitor.dart';
import '../utils/logger.dart' as app_logger;
import 'sync_event.dart';
import 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  StreamSubscription<BackgroundSyncStatus>? _backgroundSyncSubscription;

  SyncBloc() : super(SyncInitial()) {
    on<LoadSettings>(_onLoadSettings);
    on<SaveServerConfig>(_onSaveServerConfig);
    on<SaveSchedulerConfig>(_onSaveSchedulerConfig);
    on<AddSyncedFolder>(_onAddSyncedFolder);
    on<RemoveSyncedFolder>(_onRemoveSyncedFolder);
    on<UpdateSyncedFolder>(_onUpdateSyncedFolder);
    on<TestConnection>(_onTestConnection);
    on<StartSync>(_onStartSync);
    on<LoadSyncHistory>(_onLoadSyncHistory);
    on<SetAutoDelete>(_onSetAutoDelete);
    on<RequestPermissions>(_onRequestPermissions);
    on<SwitchToBackgroundSync>(_onSwitchToBackgroundSync);
    on<UpdateBackgroundSyncProgress>(_onUpdateBackgroundSyncProgress);
    
    // Start monitoring background sync when bloc is created
    _startBackgroundSyncMonitoring();
  }

  void _startBackgroundSyncMonitoring() {
    BackgroundSyncMonitor.startMonitoring();
    _backgroundSyncSubscription = BackgroundSyncMonitor.statusStream.listen((status) {
      add(UpdateBackgroundSyncProgress(status));
    });
  }

  Future<void> _onLoadSettings(LoadSettings event, Emitter<SyncState> emit) async {
    emit(SyncLoading());
    
    try {
      final serverConfig = await SettingsService.getServerConfig();
      final schedulerConfig = await SettingsService.getSchedulerConfig();
      final syncedFolders = await DatabaseService.getAllSyncedFolders();
      final syncHistory = await DatabaseService.getAllSyncRecords();
      final recentActivityRecords = await DatabaseService.getLatestSyncSessionRecords();
      final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
      
      bool permissionsGranted;
      try {
        permissionsGranted = await PermissionService.hasStoragePermission();
      } catch (e) {
        app_logger.Logger.error('Error checking permissions', error: e);
        permissionsGranted = false;
      }

      emit(SyncLoaded(
        serverConfig: serverConfig,
        schedulerConfig: schedulerConfig,
        syncedFolders: syncedFolders,
        syncHistory: syncHistory,
        recentActivityRecords: recentActivityRecords,
        autoDeleteEnabled: autoDeleteEnabled,
        permissionsGranted: permissionsGranted,
      ));
    } catch (e) {
      emit(SyncError('Failed to load settings: $e'));
    }
  }

  Future<void> _onSaveServerConfig(SaveServerConfig event, Emitter<SyncState> emit) async {
    try {
      await SettingsService.saveServerConfig(event.config);
      
      // Reload all settings to ensure consistency
      add(LoadSettings());
    } catch (e) {
      emit(SyncError('Failed to save server config: $e'));
    }
  }

  Future<void> _onSaveSchedulerConfig(SaveSchedulerConfig event, Emitter<SyncState> emit) async {
    try {
      await SettingsService.saveSchedulerConfig(event.config);
      await BackgroundSyncService.scheduleSync(event.config);
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        emit(currentState.copyWith(schedulerConfig: event.config));
      }
    } catch (e) {
      emit(SyncError('Failed to save scheduler config: $e'));
    }
  }

  Future<void> _onAddSyncedFolder(AddSyncedFolder event, Emitter<SyncState> emit) async {
    try {
      app_logger.Logger.info('Adding synced folder: ${event.folder.name} at ${event.folder.localPath}');
      await DatabaseService.insertSyncedFolder(event.folder);
      app_logger.Logger.info('Successfully saved folder to database');
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        final updatedFolders = List<SyncedFolder>.from(currentState.syncedFolders)
          ..add(event.folder);
        app_logger.Logger.info('Updating state with ${updatedFolders.length} folders');
        emit(currentState.copyWith(syncedFolders: updatedFolders));
      }
    } catch (e) {
      app_logger.Logger.error('Failed to add synced folder', error: e);
      emit(SyncError('Failed to add synced folder: $e'));
    }
  }

  Future<void> _onRemoveSyncedFolder(RemoveSyncedFolder event, Emitter<SyncState> emit) async {
    try {
      await DatabaseService.deleteSyncedFolder(event.folderId);
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        final updatedFolders = currentState.syncedFolders
            .where((folder) => folder.id != event.folderId)
            .toList();
        emit(currentState.copyWith(syncedFolders: updatedFolders));
      }
    } catch (e) {
      emit(SyncError('Failed to remove synced folder: $e'));
    }
  }

  Future<void> _onUpdateSyncedFolder(UpdateSyncedFolder event, Emitter<SyncState> emit) async {
    try {
      await DatabaseService.updateSyncedFolder(event.folder);
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        final updatedFolders = currentState.syncedFolders.map((folder) {
          return folder.id == event.folder.id ? event.folder : folder;
        }).toList();
        emit(currentState.copyWith(syncedFolders: updatedFolders));
      }
    } catch (e) {
      emit(SyncError('Failed to update synced folder: $e'));
    }
  }

  Future<void> _onTestConnection(TestConnection event, Emitter<SyncState> emit) async {
    if (state is! SyncLoaded) return;
    
    final currentState = state as SyncLoaded;
    final serverConfig = currentState.serverConfig;
    
    if (serverConfig == null) {
      emit(const ConnectionTestFailure('No server configuration found'));
      return;
    }

    emit(ConnectionTesting());
    
    try {
      final result = await FileSyncService.testConnectionWithDetection(serverConfig);
      final success = result['success'] ?? false;
      final detectedServerType = result['serverType'] as ServerType?;
      
      if (success) {
        // If server type was detected and is different, update the config
        if (detectedServerType != null && detectedServerType != serverConfig.serverType) {
          app_logger.Logger.info('🔍 Server type detected: ${detectedServerType.name}');
          final updatedConfig = serverConfig.copyWith(serverType: detectedServerType);
          await SettingsService.saveServerConfig(updatedConfig);
          
          // Reload settings to reflect the updated server type
          add(LoadSettings());
        }
        
        emit(ConnectionTestSuccess());
      } else {
        final error = result['error'] as String?;
        emit(ConnectionTestFailure(error ?? 'Connection failed'));
      }
    } catch (e) {
      emit(ConnectionTestFailure('Connection test failed: $e'));
    }
  }

  Future<void> _onStartSync(StartSync event, Emitter<SyncState> emit) async {
    if (state is! SyncLoaded) return;
    
    final currentState = state as SyncLoaded;
    final serverConfig = currentState.serverConfig;
    
    if (serverConfig == null) {
      emit(const SyncError('No server configuration found'));
      return;
    }

    try {
      // Get enabled folders
      final enabledFolders = currentState.syncedFolders
          .where((folder) => folder.enabled)
          .toList();
      
      if (enabledFolders.isEmpty) {
        emit(const SyncError('No enabled folders found'));
        return;
      }

      app_logger.Logger.info('🚀 Starting background sync');

      // Always use background sync as the primary method
      await BackgroundSyncService.runSyncNow();
      
      // Return to loaded state to show normal UI - progress will be shown via monitoring
      add(LoadSettings());
      
    } catch (e) {
      app_logger.Logger.error('Failed to start background sync', error: e);
      emit(SyncError('Failed to start sync: $e'));
      
      // Return to SyncLoaded state immediately after showing error
      add(LoadSettings());
    }
  }

  Future<void> _onLoadSyncHistory(LoadSyncHistory event, Emitter<SyncState> emit) async {
    if (state is! SyncLoaded) return;
    
    try {
      final syncHistory = await DatabaseService.getAllSyncRecords();
      final recentActivityRecords = await DatabaseService.getLatestSyncSessionRecords();
      final currentState = state as SyncLoaded;
      emit(currentState.copyWith(
        syncHistory: syncHistory,
        recentActivityRecords: recentActivityRecords,
      ));
    } catch (e) {
      emit(SyncError('Failed to load sync history: $e'));
    }
  }

  Future<void> _onSetAutoDelete(SetAutoDelete event, Emitter<SyncState> emit) async {
    try {
      await SettingsService.setAutoDeleteEnabled(event.enabled);
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        emit(currentState.copyWith(autoDeleteEnabled: event.enabled));
      }
    } catch (e) {
      emit(SyncError('Failed to set auto-delete: $e'));
    }
  }

  Future<void> _onRequestPermissions(RequestPermissions event, Emitter<SyncState> emit) async {
    try {
      final granted = await PermissionService.requestAllPermissions();
      
      if (state is SyncLoaded) {
        final currentState = state as SyncLoaded;
        emit(currentState.copyWith(permissionsGranted: granted));
      }
      
      if (!granted) {
        emit(const PermissionRequired(['Storage', 'Notification']));
      }
    } catch (e) {
      emit(SyncError('Failed to request permissions: $e'));
    }
  }

  Future<void> _onSwitchToBackgroundSync(SwitchToBackgroundSync event, Emitter<SyncState> emit) async {
    // This is called when the app goes to background
    // Background sync is already running independently, so we just ensure it continues
    app_logger.Logger.info('App switched to background - background sync continues');
    
    // If we're currently in any sync state, just return to loaded state
    // The background sync will continue independently
    if (state is SyncLoaded) return;
    
    // Reload settings to refresh the state
    add(LoadSettings());
  }

  Future<void> _onUpdateBackgroundSyncProgress(UpdateBackgroundSyncProgress event, Emitter<SyncState> emit) async {
    final status = event.status;
    
    if (status.isActive && state is SyncLoaded) {
      // Show detailed background sync progress in the UI
      final loadedState = state as SyncLoaded;
      final estimatedTimeRemaining = status.uploadSpeed > 0 && status.fileSize > status.uploadedBytes
        ? Duration(seconds: ((status.fileSize - status.uploadedBytes) / status.uploadSpeed).round())
        : Duration.zero;
        
      emit(SyncInProgress(
        currentFile: status.currentFile,
        totalFiles: status.totalFiles,
        currentFileName: status.currentFileName,
        fileSize: status.fileSize,
        uploadedBytes: status.uploadedBytes,
        uploadSpeed: status.uploadSpeed,
        estimatedTimeRemaining: estimatedTimeRemaining,
        syncedFolders: loadedState.syncedFolders,
        syncHistory: loadedState.syncHistory,
        recentActivityRecords: loadedState.recentActivityRecords,
      ));
    } else if (status.isActive && state is SyncInProgress) {
      // Update progress while sync is ongoing
      final inProgressState = state as SyncInProgress;
      final estimatedTimeRemaining = status.uploadSpeed > 0 && status.fileSize > status.uploadedBytes
        ? Duration(seconds: ((status.fileSize - status.uploadedBytes) / status.uploadSpeed).round())
        : Duration.zero;
        
      emit(SyncInProgress(
        currentFile: status.currentFile,
        totalFiles: status.totalFiles,
        currentFileName: status.currentFileName,
        fileSize: status.fileSize,
        uploadedBytes: status.uploadedBytes,
        uploadSpeed: status.uploadSpeed,
        estimatedTimeRemaining: estimatedTimeRemaining,
        syncedFolders: inProgressState.syncedFolders,
        syncHistory: inProgressState.syncHistory,
        recentActivityRecords: inProgressState.recentActivityRecords,
      ));
    } else if (!status.isActive && state is SyncInProgress) {
      // Background sync completed - check if all files have been processed
      final inProgressState = state as SyncInProgress;
      final totalProcessed = status.syncedCount + status.errorCount;
      
      if (totalProcessed >= inProgressState.totalFiles && inProgressState.totalFiles > 0) {
        // All files have been processed, show completion state
        emit(SyncSuccess(
          syncedCount: status.syncedCount,
          errorCount: status.errorCount,
        ));
        
        // Return to loaded state immediately after showing completion
        add(LoadSettings());
      } else {
        // Sync is marked as inactive but not all files processed yet - keep monitoring
        // This handles edge cases where status updates are delayed
        app_logger.Logger.debug('Sync inactive but only $totalProcessed/${inProgressState.totalFiles} files processed');
      }
    } else if (!status.isActive && state is SyncSuccess) {
      // Already in success state and sync is inactive - ensure we return to loaded state
      try {
        add(LoadSettings());
      } catch (e) {
        app_logger.Logger.error('Error reloading settings after sync completion', error: e);
      }
    }
  }
  
  @override
  Future<void> close() {
    _backgroundSyncSubscription?.cancel();
    BackgroundSyncMonitor.stopMonitoring();
    return super.close();
  }
}
