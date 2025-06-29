import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'server_config_bloc.dart';
import 'synced_folders_bloc.dart';
import 'sync_operation_bloc.dart';
import 'app_settings_bloc.dart';

/// Helper class to easily access BLoCs throughout the app
class AppBlocProvider {
  /// Get ServerConfigBloc from context
  static ServerConfigBloc serverConfig(BuildContext context) {
    return BlocProvider.of<ServerConfigBloc>(context);
  }
  
  /// Get SyncedFoldersBloc from context
  static SyncedFoldersBloc syncedFolders(BuildContext context) {
    return BlocProvider.of<SyncedFoldersBloc>(context);
  }
  
  /// Get SyncOperationBloc from context
  static SyncOperationBloc syncOperation(BuildContext context) {
    return BlocProvider.of<SyncOperationBloc>(context);
  }
  
  /// Get AppSettingsBloc from context
  static AppSettingsBloc appSettings(BuildContext context) {
    return BlocProvider.of<AppSettingsBloc>(context);
  }
}

/// Extension for easy BLoC access
extension BuildContextBlocExtension on BuildContext {
  ServerConfigBloc get serverConfigBloc => AppBlocProvider.serverConfig(this);
  SyncedFoldersBloc get syncedFoldersBloc => AppBlocProvider.syncedFolders(this);
  SyncOperationBloc get syncOperationBloc => AppBlocProvider.syncOperation(this);
  AppSettingsBloc get appSettingsBloc => AppBlocProvider.appSettings(this);
}
