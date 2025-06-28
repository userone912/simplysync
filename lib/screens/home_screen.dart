import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/sync_record.dart';
import '../models/synced_folder.dart';
import '../models/scheduler_config.dart';
import '../services/database_service.dart';
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
  late AnimationController _liveUpdateAnimationController;
  late AnimationController _statsUpdateAnimationController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _liveUpdateAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _statsUpdateAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncAnimationController.dispose();
    _liveUpdateAnimationController.dispose();
    _statsUpdateAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // When app resumes, check if we need to refresh permissions
      // This helps handle cases where permissions were revoked while app was minimized
      
      // Always refresh settings when resuming to check permissions
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          context.read<SyncBloc>().add(LoadSettings());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<SyncBloc, SyncState>(
        listener: (context, state) {
          // Control sync animation
          if (state is SyncInProgress) {
            _syncAnimationController.repeat();
          } else {
            _syncAnimationController.stop();
            _syncAnimationController.reset();
          }
          
          if (state is SyncError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
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
          } else if (state is ConnectionTestSuccess) {
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
        builder: (context, state) {
          return IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDashboard(state),
              const FoldersScreen(),
              const HistoryScreen(),
              const SettingsScreen(),
            ],
          );
        },
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
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                final currentState = context.read<SyncBloc>().state;
                
                // If permissions are required, request them first
                if (currentState is PermissionRequired) {
                  context.read<SyncBloc>().add(RequestPermissions());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔐 Requesting permissions...'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                
                context.read<SyncBloc>().add(StartSync());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🚀 Sync started! Check notifications for progress.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Sync Now'),
            )
          : null,
    );
  }

  Widget _buildDashboard(SyncState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('simplySync'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(state),
                  const SizedBox(height: 16),
                  // Show background sync status if we have scheduler config
                  if (state is SyncLoaded) ...[
                    _buildBackgroundSyncStatus(state.schedulerConfig),
                    const SizedBox(height: 16),
                  ],
                  _buildQuickActions(state),
                  const SizedBox(height: 16),
                  _buildStatsCard(state),
                  const SizedBox(height: 16),
                  _buildRecentActivity(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(SyncState state) {
    Color statusColor = Colors.grey;
    String statusText = 'Not configured';
    IconData statusIcon = Icons.warning;

    if (state is SyncInitial || state is SyncLoading) {
      statusColor = Colors.blue;
      statusText = 'Loading...';
      statusIcon = Icons.hourglass_empty;
    } else if (state is SyncError) {
      statusColor = Colors.red;
      statusText = 'Error: ${state.message}';
      statusIcon = Icons.error;
    } else if (state is SyncLoaded) {
      if (state.serverConfig != null && state.syncedFolders.isNotEmpty) {
        statusColor = Colors.green;
        statusText = 'Ready to sync';
        statusIcon = Icons.check_circle;
      } else if (state.serverConfig == null) {
        statusColor = Colors.orange;
        statusText = 'Server not configured';
        statusIcon = Icons.settings;
      } else if (state.syncedFolders.isEmpty) {
        statusColor = Colors.orange;
        statusText = 'No folders selected';
        statusIcon = Icons.folder_open;
      }
    } else if (state is SyncInProgress) {
      statusColor = Colors.blue;
      statusText = 'Syncing files...';
      statusIcon = Icons.sync;
    } else if (state is SyncSuccess) {
      statusColor = Colors.green;
      if (state.syncedCount > 0 || state.errorCount > 0) {
        statusText = 'Sync completed: ${state.syncedCount} files synced';
        if (state.errorCount > 0) {
          statusText += ', ${state.errorCount} errors';
        }
      } else {
        statusText = 'Sync completed - No new files to sync';
      }
      statusIcon = Icons.check_circle;
    } else if (state is ConnectionTesting) {
      statusColor = Colors.blue;
      statusText = 'Testing connection...';
      statusIcon = Icons.wifi_find;
    } else if (state is ConnectionTestSuccess) {
      statusColor = Colors.green;
      statusText = 'Connection test successful';
      statusIcon = Icons.wifi;
    } else if (state is ConnectionTestFailure) {
      statusColor = Colors.red;
      statusText = 'Connection test failed';
      statusIcon = Icons.wifi_off;
    } else if (state is PermissionRequired) {
      statusColor = Colors.orange;
      statusText = 'Permissions required';
      statusIcon = Icons.security;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Add animation to sync icon when syncing
                state is SyncInProgress
                    ? RotationTransition(
                        turns: Tween(begin: 0.0, end: 1.0).animate(
                          CurvedAnimation(parent: _syncAnimationController, curve: Curves.linear),
                        ),
                        child: Icon(
                          statusIcon,
                          color: statusColor,
                          size: 32,
                        ),
                      )
                    : Icon(
                        statusIcon,
                        color: statusColor,
                        size: 32,
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(SyncState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                  child: FilledButton.icon(
                    onPressed: state is SyncInProgress
                        ? null
                        : () {
                            // If permissions are required, request them first
                            if (state is PermissionRequired) {
                              context.read<SyncBloc>().add(RequestPermissions());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔐 Requesting permissions...'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            
                            context.read<SyncBloc>().add(StartSync());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🚀 Sync started! Check notifications for progress.'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                    icon: state is PermissionRequired ? const Icon(Icons.security) : const Icon(Icons.upload),
                    label: state is PermissionRequired ? const Text('Grant Permissions') : const Text('Sync Now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<SyncBloc>().add(TestConnection());
                    },
                    icon: const Icon(Icons.network_check),
                    label: const Text('Test Connection'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(SyncState state) {
    // Use same approach as History Screen with FutureBuilder for consistent data access
    return FutureBuilder<List<SyncRecord>>(
      future: DatabaseService.getAllSyncRecords(),
      builder: (context, historySnapshot) {
        // Use data from state if available and fresh, otherwise use database data
        List<SyncRecord> syncHistory = [];
        List<SyncedFolder> syncedFolders = [];
        
        if (state is SyncLoaded) {
          // Prefer state data when in SyncLoaded state as it's most current
          syncHistory = state.syncHistory;
          syncedFolders = state.syncedFolders;
        } else if (state is SyncInProgress) {
          // Use state data during sync for live updates, but keep syncedFolders stable
          syncHistory = state.syncHistory;
          syncedFolders = state.syncedFolders;
        } else if (historySnapshot.hasData) {
          // Use database data for other states (SyncSuccess, etc.)
          syncHistory = historySnapshot.data!;
          // syncedFolders will remain empty as we don't have access to them here
        } else if (historySnapshot.connectionState == ConnectionState.waiting) {
          // Show loading while fetching from database
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return _buildStatsCardContent(
          syncHistory: syncHistory,
          syncedFolders: syncedFolders,
          state: state, // Pass the current state for live statistics
          isLive: state is SyncInProgress,
        );
      },
    );
  }

  Widget _buildStatsCardContent({
    required List<SyncRecord> syncHistory,
    required List<SyncedFolder> syncedFolders,
    required SyncState state, // Add state parameter for live statistics
    required bool isLive,
  }) {
    final completed = syncHistory.where((r) => r.status == SyncStatus.completed).length;
    final failed = syncHistory.where((r) => r.status == SyncStatus.failed).length;
    final totalFolders = syncedFolders.length;
    
    // Use live statistics during sync for "Total Files" and "Synced" counts
    String totalFilesText;
    String syncedText;
    
    if (state is SyncInProgress) {
      // During sync, show live counts from the sync progress
      totalFilesText = state.totalFiles.toString();
      syncedText = (state.currentFile > 0 ? state.currentFile - 1 : 0).toString();
    } else {
      // For other states, use database/history data
      totalFilesText = syncHistory.length.toString();
      syncedText = completed.toString();
    }

    return Card(
      elevation: isLive ? 4 : 1,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = 2; // Navigate to History tab
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Statistics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (isLive)
                    AnimatedBuilder(
                      animation: _liveUpdateAnimationController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 0.8 + 0.2 * (0.5 + 0.5 * 
                            (1.0 + _liveUpdateAnimationController.value)),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem('Folders', totalFolders.toString(), Icons.folder),
                  ),
                  Expanded(
                    child: _buildStatItem('Total Files', totalFilesText, Icons.insert_drive_file),
                  ),
                  Expanded(
                    child: _buildStatItem('Synced', syncedText, Icons.check_circle),
                  ),
                  Expanded(
                    child: _buildStatItem('Failed', failed.toString(), Icons.error),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 24,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }

  Widget _buildRecentActivity(SyncState state) {
    // Use same approach as History Screen with FutureBuilder for consistent data access
    return FutureBuilder<List<SyncRecord>>(
      future: DatabaseService.getLatestSyncSessionRecords(),
      builder: (context, recentSnapshot) {
        // Use data from state if available and fresh, otherwise use database data
        List<SyncRecord> recentSyncs = [];
        
        if (state is SyncLoaded) {
          // Prefer state data when in SyncLoaded state as it's most current
          recentSyncs = state.recentActivityRecords;
        } else if (recentSnapshot.hasData) {
          // Use database data for other states (SyncInProgress, SyncSuccess, etc.)
          recentSyncs = recentSnapshot.data!;
        } else if (recentSnapshot.connectionState == ConnectionState.waiting) {
          // Show loading while fetching from database
          return const Center(child: CircularProgressIndicator());
        }

        return _buildRecentActivityContent(recentSyncs);
      },
    );
  }

  Widget _buildBackgroundSyncStatus(SchedulerConfig schedulerConfig) {
    final enabled = schedulerConfig.enabled;
    final Color statusColor = enabled ? Colors.green : Colors.grey;
    final IconData statusIcon = enabled ? Icons.schedule : Icons.schedule_outlined;
    
    String statusText;
    
    if (enabled) {
      if (schedulerConfig.isDailySync) {
        final hour = schedulerConfig.dailySyncHour.toString().padLeft(2, '0');
        final minute = schedulerConfig.dailySyncMinute.toString().padLeft(2, '0');
        final nextSync = _getNextDailySyncTime(schedulerConfig.dailySyncHour, schedulerConfig.dailySyncMinute);
        statusText = 'Daily at $hour:$minute (next: $nextSync)';
      } else {
        final nextSync = _getNextIntervalSyncTime(schedulerConfig.intervalMinutes);
        statusText = 'Every ${schedulerConfig.intervalMinutes} minutes (next: $nextSync)';
      }
    } else {
      statusText = 'Disabled';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Background Sync',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'ACTIVE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getNextDailySyncTime(int hour, int minute) {
    final now = DateTime.now();
    var nextSync = DateTime(now.year, now.month, now.day, hour, minute);
    
    // If the time has already passed today, schedule for tomorrow
    if (nextSync.isBefore(now)) {
      nextSync = nextSync.add(const Duration(days: 1));
    }
    
    return _formatTime12Hour(nextSync);
  }

  String _getNextIntervalSyncTime(int intervalMinutes) {
    final now = DateTime.now();
    final nextSync = now.add(Duration(minutes: intervalMinutes));
    return _formatTime12Hour(nextSync);
  }

  String _formatTime12Hour(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute;
    final isPM = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    final period = isPM ? 'PM' : 'AM';
    
    // If it's today, just show time
    final now = DateTime.now();
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      return '$displayHour:$minuteStr $period';
    } else {
      // If it's tomorrow, show "Tomorrow HH:MM AM/PM"
      return 'Tomorrow $displayHour:$minuteStr $period';
    }
  }

  Widget _buildRecentActivityContent(List<SyncRecord> recentSyncs) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Row(
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (recentSyncs.isNotEmpty)
                  Text(
                    '${recentSyncs.length} file${recentSyncs.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                if (recentSyncs.length > 5)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 2; // Navigate to History tab
                      });
                    },
                    child: const Text('View All'),
                  ),
              ],
            ),
          ),
          if (recentSyncs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No files from latest sync session',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...recentSyncs.take(5).map((record) => _buildActivityListTile(record)),
        ],
      ),
    );
  }

  Widget _buildActivityListTile(SyncRecord record) {
    Color statusColor;
    IconData statusIcon;

    switch (record.status) {
      case SyncStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case SyncStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case SyncStatus.syncing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      case SyncStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.2),
        child: Icon(
          statusIcon,
          color: statusColor,
        ),
      ),
      title: Text(
        record.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatFileSize(record.fileSize)} • ${_formatRelativeTime(record.syncedAt ?? record.lastModified)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return _formatDateTime(dateTime);
    }
  }
}
