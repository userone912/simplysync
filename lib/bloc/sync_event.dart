import 'package:equatable/equatable.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../models/synced_folder.dart';
import '../services/background_sync_monitor.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettings extends SyncEvent {}

class SaveServerConfig extends SyncEvent {
  final ServerConfig config;

  const SaveServerConfig(this.config);

  @override
  List<Object> get props => [config];
}

class SaveSchedulerConfig extends SyncEvent {
  final SchedulerConfig config;

  const SaveSchedulerConfig(this.config);

  @override
  List<Object> get props => [config];
}

class AddSyncedFolder extends SyncEvent {
  final SyncedFolder folder;

  const AddSyncedFolder(this.folder);

  @override
  List<Object> get props => [folder];
}

class RemoveSyncedFolder extends SyncEvent {
  final String folderId;

  const RemoveSyncedFolder(this.folderId);

  @override
  List<Object> get props => [folderId];
}

class UpdateSyncedFolder extends SyncEvent {
  final SyncedFolder folder;

  const UpdateSyncedFolder(this.folder);

  @override
  List<Object> get props => [folder];
}

class TestConnection extends SyncEvent {}

class StartSync extends SyncEvent {}

class LoadSyncHistory extends SyncEvent {}

class SetAutoDelete extends SyncEvent {
  final bool enabled;

  const SetAutoDelete(this.enabled);

  @override
  List<Object> get props => [enabled];
}

class RequestPermissions extends SyncEvent {}

class SwitchToBackgroundSync extends SyncEvent {}

class UpdateBackgroundSyncProgress extends SyncEvent {
  final BackgroundSyncStatus status;

  const UpdateBackgroundSyncProgress(this.status);

  @override
  List<Object> get props => [status];
}
