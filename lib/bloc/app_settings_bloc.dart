import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/scheduler_config.dart';
import '../services/settings_service.dart';
import '../services/permission_service.dart';
import '../services/background_sync_service.dart';
import '../utils/logger.dart' as app_logger;

// Events
abstract class AppSettingsEvent extends Equatable {
  const AppSettingsEvent();
  @override
  List<Object?> get props => [];
}

class LoadAppSettings extends AppSettingsEvent {}

class SaveSchedulerConfig extends AppSettingsEvent {
  final SchedulerConfig config;
  const SaveSchedulerConfig(this.config);
  @override
  List<Object> get props => [config];
}

class SetAutoDelete extends AppSettingsEvent {
  final bool enabled;
  const SetAutoDelete(this.enabled);
  @override
  List<Object> get props => [enabled];
}

class RequestPermissions extends AppSettingsEvent {}

class SetConflictResolutionMode extends AppSettingsEvent {
  final String mode;
  const SetConflictResolutionMode(this.mode);
  @override
  List<Object> get props => [mode];
}

// States
abstract class AppSettingsState extends Equatable {
  const AppSettingsState();
  @override
  List<Object?> get props => [];
}

class AppSettingsInitial extends AppSettingsState {}

class AppSettingsLoading extends AppSettingsState {}

class AppSettingsLoaded extends AppSettingsState {
  final SchedulerConfig schedulerConfig;
  final bool autoDeleteEnabled;
  final bool permissionsGranted;
  final String conflictResolutionMode;
  final DateTime? lastSchedulerUpdate;

  const AppSettingsLoaded({
    required this.schedulerConfig,
    required this.autoDeleteEnabled,
    required this.permissionsGranted,
    this.conflictResolutionMode = 'append',
    this.lastSchedulerUpdate,
  });

  AppSettingsLoaded copyWith({
    SchedulerConfig? schedulerConfig,
    bool? autoDeleteEnabled,
    bool? permissionsGranted,
    String? conflictResolutionMode,
    DateTime? lastSchedulerUpdate,
  }) {
    return AppSettingsLoaded(
      schedulerConfig: schedulerConfig ?? this.schedulerConfig,
      autoDeleteEnabled: autoDeleteEnabled ?? this.autoDeleteEnabled,
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
      conflictResolutionMode: conflictResolutionMode ?? this.conflictResolutionMode,
      lastSchedulerUpdate: lastSchedulerUpdate ?? this.lastSchedulerUpdate,
    );
  }

  @override
  List<Object?> get props => [schedulerConfig, autoDeleteEnabled, permissionsGranted, conflictResolutionMode, lastSchedulerUpdate];
}

class AppSettingsError extends AppSettingsState {
  final String message;
  const AppSettingsError(this.message);
  @override
  List<Object> get props => [message];
}

class PermissionRequired extends AppSettingsState {
  final List<String> missingPermissions;
  const PermissionRequired(this.missingPermissions);
  @override
  List<Object> get props => [missingPermissions];
}

// BLoC
class AppSettingsBloc extends Bloc<AppSettingsEvent, AppSettingsState> {
  AppSettingsBloc() : super(AppSettingsInitial()) {
    on<LoadAppSettings>(_onLoadAppSettings);
    on<SaveSchedulerConfig>(_onSaveSchedulerConfig);
    on<SetAutoDelete>(_onSetAutoDelete);
    on<RequestPermissions>(_onRequestPermissions);
    on<SetConflictResolutionMode>(_onSetConflictResolutionMode);
  }

  Future<void> _onLoadAppSettings(LoadAppSettings event, Emitter<AppSettingsState> emit) async {
    emit(AppSettingsLoading());
    
    try {
      final schedulerConfig = await SettingsService.getSchedulerConfig();
      final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
      String conflictResolutionMode = await SettingsService.getConflictResolutionMode();
      final lastSchedulerUpdate = await SettingsService.getLastSchedulerUpdate();
      bool permissionsGranted;
      try {
        permissionsGranted = await PermissionService.hasStoragePermission();
      } catch (e) {
        app_logger.Logger.error('Error checking permissions', error: e);
        permissionsGranted = false;
      }

      emit(AppSettingsLoaded(
        schedulerConfig: schedulerConfig,
        autoDeleteEnabled: autoDeleteEnabled,
        permissionsGranted: permissionsGranted,
        conflictResolutionMode: conflictResolutionMode,
        lastSchedulerUpdate: lastSchedulerUpdate,
      ));
    } catch (e) {
      emit(AppSettingsError('Failed to load settings: $e'));
    }
  }

  Future<void> _onSaveSchedulerConfig(SaveSchedulerConfig event, Emitter<AppSettingsState> emit) async {
    try {
      await SettingsService.saveSchedulerConfig(event.config);
      await BackgroundSyncService.scheduleSync(event.config);
      final lastSchedulerUpdate = await SettingsService.getLastSchedulerUpdate();
      if (state is AppSettingsLoaded) {
        final currentState = state as AppSettingsLoaded;
        emit(currentState.copyWith(schedulerConfig: event.config, lastSchedulerUpdate: lastSchedulerUpdate));
      }
    } catch (e) {
      emit(AppSettingsError('Failed to save scheduler config: $e'));
    }
  }

  Future<void> _onSetAutoDelete(SetAutoDelete event, Emitter<AppSettingsState> emit) async {
    try {
      await SettingsService.setAutoDeleteEnabled(event.enabled);
      
      if (state is AppSettingsLoaded) {
        final currentState = state as AppSettingsLoaded;
        emit(currentState.copyWith(autoDeleteEnabled: event.enabled));
      }
    } catch (e) {
      emit(AppSettingsError('Failed to set auto-delete: $e'));
    }
  }

  Future<void> _onRequestPermissions(RequestPermissions event, Emitter<AppSettingsState> emit) async {
    try {
      final granted = await PermissionService.requestAllPermissions();
      
      if (state is AppSettingsLoaded) {
        final currentState = state as AppSettingsLoaded;
        emit(currentState.copyWith(permissionsGranted: granted));
      }
      
      if (!granted) {
        emit(const PermissionRequired(['Storage', 'Notification']));
      }
    } catch (e) {
      emit(AppSettingsError('Failed to request permissions: $e'));
    }
  }

  Future<void> _onSetConflictResolutionMode(SetConflictResolutionMode event, Emitter<AppSettingsState> emit) async {
    try {
      await SettingsService.setConflictResolutionMode(event.mode);
      
      if (state is AppSettingsLoaded) {
        final currentState = state as AppSettingsLoaded;
        emit(currentState.copyWith(conflictResolutionMode: event.mode));
      }
    } catch (e) {
      emit(AppSettingsError('Failed to set conflict resolution mode: $e'));
    }
  }
}
