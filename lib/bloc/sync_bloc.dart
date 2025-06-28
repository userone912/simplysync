import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/synced_folder.dart';
import '../models/server_config.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import '../services/file_sync_service.dart';
import '../services/file_scanner_service.dart';
import '../services/background_sync_service.dart';
import '../utils/logger.dart' as app_logger;
import 'sync_event.dart';
import 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
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
  }

  Future<void> _onLoadSettings(LoadSettings event, Emitter<SyncState> emit) async {
    emit(SyncLoading());
    
    try {
      final serverConfig = await SettingsService.getServerConfig();
      final schedulerConfig = await SettingsService.getSchedulerConfig();
      final syncedFolders = await DatabaseService.getAllSyncedFolders();
      final syncHistory = await DatabaseService.getAllSyncRecords();
      final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
      final permissionsGranted = await PermissionService.hasStoragePermission();

      emit(SyncLoaded(
        serverConfig: serverConfig,
        schedulerConfig: schedulerConfig,
        syncedFolders: syncedFolders,
        syncHistory: syncHistory,
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

      // Scan for files to show immediate feedback
      final files = await FileScannerService.scanFoldersForFiles(enabledFolders);
      
      if (files.isEmpty) {
        emit(const SyncSuccess(syncedCount: 0, errorCount: 0));
        return;
      }

      app_logger.Logger.info('🚀 Starting background sync with notifications for ${files.length} files');

      // Show initial progress state
      emit(SyncInProgress(
        currentFile: 0,
        totalFiles: files.length,
        currentFileName: 'Preparing sync...',
        fileSize: 0,
        uploadedBytes: 0,
        uploadSpeed: 0.0,
        estimatedTimeRemaining: Duration.zero,
      ));

      // Start background sync with notifications
      await BackgroundSyncService.runSyncNow();
      
      // Wait a moment for the background process to start
      await Future.delayed(const Duration(seconds: 1));
      
      // Show that sync has been moved to background
      emit(const SyncSuccess(syncedCount: 0, errorCount: 0));
      
      // Reload data after a delay to show final results
      await Future.delayed(const Duration(seconds: 3));
      add(LoadSettings());
      
    } catch (e) {
      app_logger.Logger.error('Failed to start background sync', error: e);
      emit(SyncError('Sync failed: $e'));
      
      // Return to SyncLoaded state after showing error
      await Future.delayed(const Duration(seconds: 3));
      add(LoadSettings());
    }
  }

  Future<void> _onLoadSyncHistory(LoadSyncHistory event, Emitter<SyncState> emit) async {
    if (state is! SyncLoaded) return;
    
    try {
      final syncHistory = await DatabaseService.getAllSyncRecords();
      final currentState = state as SyncLoaded;
      emit(currentState.copyWith(syncHistory: syncHistory));
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
}
