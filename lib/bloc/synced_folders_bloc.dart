import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/synced_folder.dart';
import '../services/database_service.dart';
import '../utils/logger.dart' as app_logger;

// Events
abstract class SyncedFoldersEvent extends Equatable {
  const SyncedFoldersEvent();
  @override
  List<Object?> get props => [];
}

class LoadSyncedFolders extends SyncedFoldersEvent {}

class AddSyncedFolder extends SyncedFoldersEvent {
  final SyncedFolder folder;
  const AddSyncedFolder(this.folder);
  @override
  List<Object> get props => [folder];
}

class RemoveSyncedFolder extends SyncedFoldersEvent {
  final String folderId;
  const RemoveSyncedFolder(this.folderId);
  @override
  List<Object> get props => [folderId];
}

class UpdateSyncedFolder extends SyncedFoldersEvent {
  final SyncedFolder folder;
  const UpdateSyncedFolder(this.folder);
  @override
  List<Object> get props => [folder];
}

// States
abstract class SyncedFoldersState extends Equatable {
  const SyncedFoldersState();
  @override
  List<Object?> get props => [];
}

class SyncedFoldersInitial extends SyncedFoldersState {}

class SyncedFoldersLoading extends SyncedFoldersState {}

class SyncedFoldersLoaded extends SyncedFoldersState {
  final List<SyncedFolder> folders;
  const SyncedFoldersLoaded(this.folders);
  @override
  List<Object> get props => [folders];
}

class SyncedFoldersError extends SyncedFoldersState {
  final String message;
  const SyncedFoldersError(this.message);
  @override
  List<Object> get props => [message];
}

// BLoC
class SyncedFoldersBloc extends Bloc<SyncedFoldersEvent, SyncedFoldersState> {
  SyncedFoldersBloc() : super(SyncedFoldersInitial()) {
    on<LoadSyncedFolders>(_onLoadSyncedFolders);
    on<AddSyncedFolder>(_onAddSyncedFolder);
    on<RemoveSyncedFolder>(_onRemoveSyncedFolder);
    on<UpdateSyncedFolder>(_onUpdateSyncedFolder);
  }

  Future<void> _onLoadSyncedFolders(LoadSyncedFolders event, Emitter<SyncedFoldersState> emit) async {
    emit(SyncedFoldersLoading());
    try {
      final folders = await DatabaseService.getAllSyncedFolders();
      emit(SyncedFoldersLoaded(folders));
    } catch (e) {
      emit(SyncedFoldersError('Failed to load synced folders: $e'));
    }
  }

  Future<void> _onAddSyncedFolder(AddSyncedFolder event, Emitter<SyncedFoldersState> emit) async {
    try {
      app_logger.Logger.info('Adding synced folder: ${event.folder.name} at ${event.folder.localPath}');
      await DatabaseService.insertSyncedFolder(event.folder);
      app_logger.Logger.info('Successfully saved folder to database');
      
      if (state is SyncedFoldersLoaded) {
        final currentState = state as SyncedFoldersLoaded;
        final updatedFolders = List<SyncedFolder>.from(currentState.folders)
          ..add(event.folder);
        app_logger.Logger.info('Updating state with ${updatedFolders.length} folders');
        emit(SyncedFoldersLoaded(updatedFolders));
      } else {
        // Reload if not in loaded state
        add(LoadSyncedFolders());
      }
    } catch (e) {
      app_logger.Logger.error('Failed to add synced folder', error: e);
      emit(SyncedFoldersError('Failed to add synced folder: $e'));
    }
  }

  Future<void> _onRemoveSyncedFolder(RemoveSyncedFolder event, Emitter<SyncedFoldersState> emit) async {
    try {
      await DatabaseService.deleteSyncedFolder(event.folderId);
      
      if (state is SyncedFoldersLoaded) {
        final currentState = state as SyncedFoldersLoaded;
        final updatedFolders = currentState.folders
            .where((folder) => folder.id != event.folderId)
            .toList();
        emit(SyncedFoldersLoaded(updatedFolders));
      } else {
        add(LoadSyncedFolders());
      }
    } catch (e) {
      emit(SyncedFoldersError('Failed to remove synced folder: $e'));
    }
  }

  Future<void> _onUpdateSyncedFolder(UpdateSyncedFolder event, Emitter<SyncedFoldersState> emit) async {
    try {
      await DatabaseService.updateSyncedFolder(event.folder);
      
      if (state is SyncedFoldersLoaded) {
        final currentState = state as SyncedFoldersLoaded;
        final updatedFolders = currentState.folders.map((folder) {
          return folder.id == event.folder.id ? event.folder : folder;
        }).toList();
        emit(SyncedFoldersLoaded(updatedFolders));
      } else {
        add(LoadSyncedFolders());
      }
    } catch (e) {
      emit(SyncedFoldersError('Failed to update synced folder: $e'));
    }
  }
}
