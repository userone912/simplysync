import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/server_config.dart';
import '../services/settings_service.dart';
import '../services/file_sync_service.dart';
import '../utils/logger.dart' as app_logger;

// Events
abstract class ServerConfigEvent extends Equatable {
  const ServerConfigEvent();
  @override
  List<Object?> get props => [];
}

class LoadServerConfig extends ServerConfigEvent {}

class SaveServerConfig extends ServerConfigEvent {
  final ServerConfig config;
  const SaveServerConfig(this.config);
  @override
  List<Object> get props => [config];
}

class TestConnection extends ServerConfigEvent {}

// States
abstract class ServerConfigState extends Equatable {
  const ServerConfigState();
  @override
  List<Object?> get props => [];
}

class ServerConfigInitial extends ServerConfigState {}

class ServerConfigLoading extends ServerConfigState {}

class ServerConfigLoaded extends ServerConfigState {
  final ServerConfig? config;
  const ServerConfigLoaded(this.config);
  @override
  List<Object?> get props => [config];
}

class ServerConfigError extends ServerConfigState {
  final String message;
  const ServerConfigError(this.message);
  @override
  List<Object> get props => [message];
}

class ConnectionTesting extends ServerConfigState {}

class ConnectionTestSuccess extends ServerConfigState {}

class ConnectionTestFailure extends ServerConfigState {
  final String message;
  const ConnectionTestFailure(this.message);
  @override
  List<Object> get props => [message];
}

// BLoC
class ServerConfigBloc extends Bloc<ServerConfigEvent, ServerConfigState> {
  ServerConfigBloc() : super(ServerConfigInitial()) {
    on<LoadServerConfig>(_onLoadServerConfig);
    on<SaveServerConfig>(_onSaveServerConfig);
    on<TestConnection>(_onTestConnection);
  }

  Future<void> _onLoadServerConfig(LoadServerConfig event, Emitter<ServerConfigState> emit) async {
    emit(ServerConfigLoading());
    try {
      final config = await SettingsService.getServerConfig();
      emit(ServerConfigLoaded(config));
    } catch (e) {
      emit(ServerConfigError('Failed to load server config: $e'));
    }
  }

  Future<void> _onSaveServerConfig(SaveServerConfig event, Emitter<ServerConfigState> emit) async {
    try {
      await SettingsService.saveServerConfig(event.config);
      emit(ServerConfigLoaded(event.config));
    } catch (e) {
      emit(ServerConfigError('Failed to save server config: $e'));
    }
  }

  Future<void> _onTestConnection(TestConnection event, Emitter<ServerConfigState> emit) async {
    if (state is! ServerConfigLoaded) return;
    
    final currentState = state as ServerConfigLoaded;
    final serverConfig = currentState.config;
    
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
          emit(ServerConfigLoaded(updatedConfig));
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
}
