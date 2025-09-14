import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../bloc/synced_folders_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../bloc/app_settings_bloc.dart';
import '../bloc/app_bloc_provider.dart';
import '../models/server_config.dart';
import 'simple_folders_screen.dart';
import 'simple_history_screen.dart';
import 'simple_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  late AnimationController _syncAnimationController;
  ServerConfig? _lastServerConfig;
  // For cleaner UI, use a single summary card and more whitespace

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    // Lazy load data only when dashboard tab is active
    if (_selectedIndex == 0) {
      _loadDashboardData();
    }
  }

  void _loadDashboardData() {
    // Only load data when actually needed
    context.serverConfigBloc.add(LoadServerConfig());
    context.syncedFoldersBloc.add(LoadSyncedFolders());
    context.syncOperationBloc.add(LoadSyncHistory());
    context.appSettingsBloc.add(LoadAppSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          context.serverConfigBloc.add(LoadServerConfig());
          context.syncedFoldersBloc.add(LoadSyncedFolders());
          context.syncOperationBloc.add(LoadSyncHistory());
          context.appSettingsBloc.add(LoadAppSettings());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: MultiBlocListener(
          listeners: [
            BlocListener<SyncOperationBloc, SyncOperationState>(
              listener: (context, state) {
                if (state is SyncInProgress) {
                  _syncAnimationController.repeat();
                } else {
                  _syncAnimationController.stop();
                  _syncAnimationController.reset();
                }
                if (state is SyncError) {
                  String errorMsg = state.message;
                  if (errorMsg.toLowerCase().contains('cancelled')) {
                    errorMsg = 'Sync cancelled by user';
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMsg),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else if (state is SyncSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Sync completed: ${state.syncedCount} files, ${state.errorCount} errors',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            BlocListener<ServerConfigBloc, ServerConfigState>(
              listener: (context, state) {
                if (state is ConnectionTestSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connection test successful!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (state is ConnectionTestFailure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connection failed: ${state.message}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              // Dashboard - simplified for background sync focus
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  children: [
                    // Main status card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              'simplySync',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildMainStatus(
                              context.watch<SyncOperationBloc>().state,
                              context.watch<AppSettingsBloc>().state,
                            ),
                            const SizedBox(height: 16),
                            _buildQuickActions(context.watch<AppSettingsBloc>().state),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Simple scheduler indicator
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildSchedulerStatus(
                          context.watch<AppSettingsBloc>().state,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Folders
              const SimpleFoldersScreen(),
              // History
              const SimpleHistoryScreen(),
              // Settings
              const SimpleSettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
            
            // Lazy load data only when switching to dashboard
            if (index == 0) {
              _loadDashboardData();
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder),
              label: 'Folders',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatus(SyncOperationState syncState, AppSettingsState settingsState) {
    String statusText = 'Ready';
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle;

    // Check server config and folder setup
    final serverConfigState = context.watch<ServerConfigBloc>().state;
    if (serverConfigState is ServerConfigLoaded && serverConfigState.config != null) {
      _lastServerConfig = serverConfigState.config;
    } else if (serverConfigState is ServerConfigInitial) {
      _lastServerConfig = null;
    }
    
    final hasServerConfig = _lastServerConfig != null;
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);

    if (!hasServerConfig) {
      statusText = 'No Server Configured';
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_off;
    } else if (!hasEnabledFolder) {
      statusText = 'No Folders Selected';
      statusColor = Colors.orange;
      statusIcon = Icons.folder_off;
    } else if (syncState is SyncInProgress) {
      statusText = 'Syncing...';
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else if (syncState is SyncError) {
      statusText = 'Sync Error';
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Column(
      children: [
        Icon(statusIcon, size: 48, color: statusColor),
        const SizedBox(height: 16),
        Text(
          statusText,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        if (syncState is SyncInProgress) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: syncState.overallProgress,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
          const SizedBox(height: 8),
          Text(
            '${syncState.currentFile}/${syncState.totalFiles} files',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _buildSchedulerStatus(AppSettingsState settingsState) {
    if (settingsState is! AppSettingsLoaded) {
      return const Text('Loading scheduler...');
    }
    
    final config = settingsState.schedulerConfig;
    
    if (!config.enabled) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, color: Colors.grey),
          const SizedBox(width: 8),
          Text('Auto Sync: Disabled', style: TextStyle(color: Colors.grey)),
        ],
      );
    }
    
    String intervalText = config.isDailySync 
        ? 'Daily at ${config.dailySyncHour}:${config.dailySyncMinute.toString().padLeft(2, '0')}'
        : 'Every ${config.intervalMinutes} min';
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, color: Colors.green),
            const SizedBox(width: 8),
            Text('Auto Sync: Enabled', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(intervalText, style: Theme.of(context).textTheme.bodyMedium),
        if (config.syncOnlyOnWifi || config.syncOnlyWhenCharging) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (config.syncOnlyOnWifi)
                Chip(label: Text('WiFi Only'), backgroundColor: Colors.blue[50]),
              if (config.syncOnlyWhenCharging)
                Chip(label: Text('Charging Only'), backgroundColor: Colors.green[50]),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildQuickActions(AppSettingsState settingsState) {
    // Use last known server config logic (persisted at State level)
    final serverConfigState = context.watch<ServerConfigBloc>().state;
    final isTestingConnection = serverConfigState is ConnectionTesting;
    final hasServerConfig = _lastServerConfig != null;
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: BlocBuilder<SyncOperationBloc, SyncOperationState>(
                    builder: (context, syncState) {
                      final isSyncInProgress = syncState is SyncInProgress || syncState is SyncCancelling;
                      
                      if (isSyncInProgress) {
                        // Show Cancel Sync button when sync is active
                        return ElevatedButton.icon(
                          onPressed: syncState is SyncCancelling ? null : () => context.syncOperationBloc.add(PauseSync()),
                          icon: Icon(syncState is SyncCancelling ? Icons.hourglass_empty : Icons.stop),
                          label: Text(syncState is SyncCancelling ? 'Cancelling...' : 'Cancel Sync'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: syncState is SyncCancelling ? Colors.orange : Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        );
                      } else {
                        // Show normal Sync Now button
                        return BlocBuilder<AppSettingsBloc, AppSettingsState>(
                          builder: (context, state) {
                            final permissionsGranted = state is AppSettingsLoaded ? state.permissionsGranted : false;
                            final canSync = permissionsGranted && hasServerConfig && hasEnabledFolder;
                            return ElevatedButton.icon(
                              onPressed: canSync ? () => context.syncOperationBloc.add(StartSyncNow()) : null,
                              icon: Icon(canSync ? Icons.sync : Icons.sync_disabled),
                              label: Text('Sync Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canSync ? Colors.blue : Colors.grey,
                                foregroundColor: Colors.white,
                              ),
                            );
                          },
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasServerConfig && !isTestingConnection
                      ? () => context.serverConfigBloc.add(TestConnection())
                      : null,
                    icon: isTestingConnection
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi),
                    label: Text(isTestingConnection ? 'Testing...' : 'Test Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasServerConfig && !isTestingConnection ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            // Debug-only foreground sync button
            // const SizedBox(height: 8),
            // if (!bool.fromEnvironment('dart.vm.product')) // Only show in debug
            //   SizedBox(
            //     width: double.infinity,
            //     child: ElevatedButton.icon(
            //       onPressed: () => context.syncOperationBloc.add(StartSyncNow()),
            //       icon: const Icon(Icons.bug_report),
            //       label: const Text('Debug Sync (Foreground)'),
            //       style: ElevatedButton.styleFrom(
            //         backgroundColor: Colors.purple,
            //         foregroundColor: Colors.white,
            //       ),
            //     ),
            //   ),
          ],
        ),
      ),
    );
  }
}
