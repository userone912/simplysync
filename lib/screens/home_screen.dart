import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../bloc/synced_folders_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../bloc/app_settings_bloc.dart';
import '../bloc/app_bloc_provider.dart';
import '../models/sync_record.dart';
import '../models/server_config.dart';
import 'settings_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  late AnimationController _syncAnimationController;

  // Cache for real-time stats/activity
  List<SyncRecord> _lastRecentActivity = [];
  List<SyncRecord> _lastSyncHistory = [];

  // Persist last known server config across rebuilds
  ServerConfig? _lastServerConfig;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
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
      // When app resumes, refresh all BLoCs
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
    return Scaffold(
      body: MultiBlocListener(
        listeners: [
          // Listen to sync operations
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
                      'Sync completed: ${state.syncedCount} files synced, ${state.errorCount} errors',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          ),
          // Listen to connection tests
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
            _buildDashboard(),
            const FoldersScreen(),
            const HistoryScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
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
    );
  }

  Widget _buildSchedulerIndicator(AppSettingsState settingsState) {
    if (settingsState is! AppSettingsLoaded) return SizedBox.shrink();
    final config = settingsState.schedulerConfig;
    final lastUpdate = settingsState.lastSchedulerUpdate;
    if (!config.enabled) {
      return Row(
        children: [
          Icon(Icons.schedule, color: Colors.grey, size: 18),
          SizedBox(width: 6),
          Text('Auto Sync: Off', style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    String modeText;
    String nextSyncText;
    DateTime baseTime = lastUpdate ?? DateTime.now();
    if (config.isDailySync) {
      final time = TimeOfDay(hour: config.dailySyncHour, minute: config.dailySyncMinute);
      modeText = 'Daily at ' + time.format(context);
      // Next sync: next daily time after last update
      DateTime nextSync = DateTime(baseTime.year, baseTime.month, baseTime.day, config.dailySyncHour, config.dailySyncMinute);
      if (nextSync.isBefore(baseTime)) {
        nextSync = nextSync.add(const Duration(days: 1));
      }
      String dayLabel = '';
      final now = DateTime.now();
      final diff = nextSync.difference(now);
      if (diff.inDays >= 2) {
        dayLabel = ', ${_weekdayName(nextSync.weekday)}';
      } else if (diff.inDays == 1 || (diff.inHours >= 24)) {
        dayLabel = ', Tomorrow';
      }
      nextSyncText = 'Next Sync at ' + TimeOfDay.fromDateTime(nextSync).format(context) + dayLabel;
    } else {
      // Interval mode
      final interval = config.intervalMinutes;
      String intervalText;
      if (interval < 60) {
        intervalText = '$interval min';
      } else if (interval % 60 == 0) {
        intervalText = '${interval ~/ 60} hr';
      } else {
        intervalText = '${interval ~/ 60} hr ${interval % 60} min';
      }
      modeText = 'Every $intervalText';
      // Next sync: next interval after last update
      DateTime nextSync = baseTime.add(Duration(minutes: interval));
      final now = DateTime.now();
      while (nextSync.isBefore(now)) {
        nextSync = nextSync.add(Duration(minutes: interval));
      }
      String dayLabel = '';
      final diff = nextSync.difference(now);
      if (diff.inDays >= 2) {
        dayLabel = ', ${_weekdayName(nextSync.weekday)}';
      } else if (diff.inDays == 1 || (diff.inHours >= 24)) {
        dayLabel = ', Tomorrow';
      }
      nextSyncText = 'Next Sync at ' + TimeOfDay.fromDateTime(nextSync).format(context) + dayLabel;
    }

    List<Widget> chips = [];
    if (config.syncOnlyOnWifi) {
      chips.add(Chip(
        avatar: Icon(Icons.wifi, size: 16, color: Colors.blue),
        label: Text('WiFi Only'),
        backgroundColor: Colors.blue[50],
        labelStyle: TextStyle(color: Colors.blue[800]),
      ));
    }
    if (config.syncOnlyWhenCharging) {
      chips.add(Chip(
        avatar: Icon(Icons.battery_charging_full, size: 16, color: Colors.green),
        label: Text('Charging Only'),
        backgroundColor: Colors.green[50],
        labelStyle: TextStyle(color: Colors.green[800]),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, color: Colors.blue, size: 18),
            SizedBox(width: 6),
            Text('Auto Sync: ON', style: TextStyle(color: Colors.blue)),
            SizedBox(width: 12),
            Text(modeText, style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500)),
          ],
        ),
        SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.access_time, color: Colors.grey, size: 16),
            SizedBox(width: 6),
            Text(nextSyncText, style: TextStyle(color: Colors.grey[700])),
          ],
        ),
        if (chips.isNotEmpty) ...[
          SizedBox(height: 6),
          Wrap(spacing: 8, children: chips),
        ],
      ],
    );
  }

  Widget _buildDashboard() {
    return BlocBuilder<SyncOperationBloc, SyncOperationState>(
      builder: (context, syncState) {
        // For real-time updates, keep track of both progress and latest activity
        List<SyncRecord> recentActivity = _lastRecentActivity;
        List<SyncRecord> syncHistory = _lastSyncHistory;
        int totalFiles = 0;
        int syncedFiles = 0;
        String? currentFileName;
        if (syncState is SyncOperationLoaded) {
          recentActivity = syncState.recentActivityRecords;
          syncHistory = syncState.syncHistory;
          _lastRecentActivity = recentActivity;
          _lastSyncHistory = syncHistory;
          syncedFiles = recentActivity.where((r) => r.status == SyncStatus.completed).length;
        } else if (syncState is SyncInProgress) {
          // Use cached values for real-time UI
          syncedFiles = recentActivity.where((r) => r.status == SyncStatus.completed).length;
        }
        if (syncState is SyncInProgress) {
          totalFiles = syncState.totalFiles;
          currentFileName = syncState.currentFileName;
        } else if (syncState is SyncOperationLoaded) {
          totalFiles = syncHistory.length;
        }
        return BlocBuilder<AppSettingsBloc, AppSettingsState>(
          builder: (context, settingsState) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 120,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('simplySync'),
                        if (syncState is SyncInProgress) ...[
                          const SizedBox(width: 8),
                          RotationTransition(
                            turns: _syncAnimationController,
                            child: const Icon(Icons.sync, size: 20),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildStatusCard(syncState, settingsState, currentFileName: currentFileName),
                      const SizedBox(height: 8),
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(() => _selectedIndex = 3), // Route to Settings tab
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _buildSchedulerIndicator(settingsState),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildQuickActions(settingsState),
                      const SizedBox(height: 16),
                      _buildStatsCard(syncState, totalFiles: totalFiles, syncedFiles: syncedFiles),
                      const SizedBox(height: 16),
                      _buildRecentActivity(syncState, recentActivity: recentActivity),
                    ]),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatusCard(SyncOperationState syncState, AppSettingsState settingsState, {String? currentFileName}) {
    String statusText = 'Ready';
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle;
    int? tabToSelect;

    // Update last known server config only if loaded or explicitly reset to initial
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
      tabToSelect = 3; // Settings tab
    } else if (!hasEnabledFolder) {
      statusText = 'No Folder selected';
      statusColor = Colors.orange;
      statusIcon = Icons.folder_off;
      tabToSelect = 1; // Folders tab
    } else if (syncState is SyncInProgress) {
      statusText = 'Syncing files...';
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else if (syncState is SyncError) {
      statusText = 'Error occurred';
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else if (settingsState is AppSettingsLoaded && !settingsState.permissionsGranted) {
      statusText = 'Permissions needed';
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    }
    return InkWell(
      onTap: tabToSelect != null
          ? () => setState(() => _selectedIndex = tabToSelect!)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (tabToSelect != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, size: 16, color: statusColor),
                  ],
                ],
              ),
              if (syncState is SyncInProgress) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: syncState.overallProgress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${syncState.currentFile}/${syncState.totalFiles} files',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${(syncState.overallProgress * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (currentFileName != null && currentFileName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Current: $currentFileName',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => context.syncOperationBloc.add(PauseSync()),
                    icon: const Icon(Icons.pause_circle_filled),
                    label: const Text('Cancel Sync'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ));
  }

  Widget _buildStatsCard(SyncOperationState syncState, {required int totalFiles, required int syncedFiles}) {
    return BlocBuilder<SyncedFoldersBloc, SyncedFoldersState>(
      builder: (context, foldersState) {
        final folderCount = foldersState is SyncedFoldersLoaded ? foldersState.folders.length : 0;
        final enabledFolders = foldersState is SyncedFoldersLoaded 
          ? foldersState.folders.where((f) => f.enabled).length 
          : 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statistics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _StatItem(
                  icon: Icons.folder,
                  label: 'Synced Folders',
                  value: '$enabledFolders/$folderCount',
                  color: Colors.blue,
                ),
                _StatItem(
                  icon: Icons.history,
                  label: 'Total Files',
                  value: '$totalFiles',
                  color: Colors.green,
                ),
                _StatItem(
                  icon: Icons.check_circle,
                  label: 'Synced Files',
                  value: '$syncedFiles',
                  color: Colors.orange,
                ),
              ],
            ),
          ),
        );
      },
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
                  child: BlocBuilder<AppSettingsBloc, AppSettingsState>(
                    builder: (context, state) {
                      final permissionsGranted = state is AppSettingsLoaded ? state.permissionsGranted : false;
                      final canSync = permissionsGranted && hasServerConfig && hasEnabledFolder;
                      return ElevatedButton.icon(
                        onPressed: () => context.syncOperationBloc.add(StartSyncNow()),
                        icon: Icon(canSync ? Icons.sync : Icons.sync_disabled),
                        label: Text('Sync Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSync ? Colors.blue : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      );
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

  Widget _buildRecentActivity(SyncOperationState syncState, {List<SyncRecord>? recentActivity}) {
    final activity = recentActivity ?? (syncState is SyncOperationLoaded ? syncState.recentActivityRecords : []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (activity.isNotEmpty)
              ...activity.take(5).map((record) => _buildActivityItem(record)).toList()
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(SyncRecord record) {
    IconData icon = Icons.file_copy;
    Color color = Colors.green;
    
    if (record.status == SyncStatus.failed) {
      icon = Icons.error;
      color = Colors.red;
    } else if (record.status == SyncStatus.syncing) {
      icon = Icons.sync;
      color = Colors.blue;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              record.fileName,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatFileSize(record.fileSize),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Helper for weekday name
  String _weekdayName(int weekday) {
    const names = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    return names[(weekday - 1) % 7];
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
