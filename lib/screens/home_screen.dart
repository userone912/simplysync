import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/sync_record.dart';
import '../models/scheduler_config.dart';
import 'settings_screen.dart';
import 'folders_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<SyncBloc, SyncState>(
        listener: (context, state) {
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
                context.read<SyncBloc>().add(StartSync());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🚀 Background sync started! Check notifications for progress.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Background Sync'),
            )
          : null,
    );
  }

  Widget _buildDashboard(SyncState state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SimplySync'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
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
            Expanded(
              child: _buildRecentActivity(state),
            ),
          ],
        ),
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
      statusText = 'Sync started - Check notifications for progress';
      statusIcon = Icons.notification_important;
    } else if (state is SyncSuccess) {
      statusColor = Colors.green;
      if (state.syncedCount == 0 && state.errorCount == 0) {
        statusText = 'Sync moved to background - Check notifications';
      } else {
        statusText = 'Sync completed successfully';
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
                Icon(
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
            // Enhanced progress information for sync in progress
            if (state is SyncInProgress) ...[
              const SizedBox(height: 16),
              _buildProgressDetails(state),
            ],
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
                            context.read<SyncBloc>().add(StartSync());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sync started in background. Check notifications for progress.'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                    icon: const Icon(Icons.upload),
                    label: const Text('Sync in Background'),
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
    int totalFolders = 0;
    int totalFiles = 0;
    int completedSyncs = 0;

    if (state is SyncLoaded) {
      totalFolders = state.syncedFolders.length;
      totalFiles = state.syncHistory.length;
      completedSyncs = state.syncHistory
          .where((record) => record.status == SyncStatus.completed)
          .length;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Folders',
                    totalFolders.toString(),
                    Icons.folder,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Total Files',
                    totalFiles.toString(),
                    Icons.insert_drive_file,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Synced',
                    completedSyncs.toString(),
                    Icons.cloud_done,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRecentActivity(SyncState state) {
    // Show loading for initial and loading states
    if (state is SyncInitial || state is SyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Show error state with retry option
    if (state is SyncError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                context.read<SyncBloc>().add(LoadSettings());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    // For all other states (SyncLoaded, SyncInProgress, SyncSuccess, etc.),
    // try to get the data from SyncLoaded state or show empty state
    List<SyncRecord> syncHistory = [];
    if (state is SyncLoaded) {
      syncHistory = state.syncHistory;
    }

    
    final recentSyncs = syncHistory
        .where((record) => record.syncedAt != null)
        .toList()
      ..sort((a, b) => b.syncedAt!.compareTo(a.syncedAt!));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
            Expanded(
              child: recentSyncs.isEmpty
                  ? const Center(
                      child: Text('No recent activity'),
                    )
                  : ListView.builder(
                      itemCount: recentSyncs.take(10).length,
                      itemBuilder: (context, index) {
                        final record = recentSyncs[index];
                        return ListTile(
                          leading: Icon(
                            record.status == SyncStatus.completed
                                ? Icons.check_circle
                                : Icons.error,
                            color: record.status == SyncStatus.completed
                                ? Colors.green
                                : Colors.red,
                          ),
                          title: Text(record.fileName),
                          subtitle: Text(
                            record.syncedAt != null
                                ? _formatDateTime(record.syncedAt!)
                                : 'Not synced',
                          ),
                          trailing: Text(
                            _formatFileSize(record.fileSize),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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

  Widget _buildProgressDetails(SyncInProgress state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Overall Progress',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${state.currentFile}/${state.totalFiles} files',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: state.overallProgress,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        
        // Current file information
        if (state.currentFileName != null) ...[
          Row(
            children: [
              Icon(
                Icons.file_upload,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Uploading: ${state.currentFileName}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // File progress bar
          if (state.fileSize > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatBytes(state.uploadedBytes),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _formatBytes(state.fileSize),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: state.fileProgress,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.green,
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          // Speed and time information
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (state.uploadSpeed > 0)
                Row(
                  children: [
                    Icon(
                      Icons.speed,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatSpeed(state.uploadSpeed)}/s',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              if (state.estimatedTimeRemaining.inSeconds > 0)
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(state.estimatedTimeRemaining),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatSpeed(double bytesPerSecond) {
    return _formatBytes(bytesPerSecond.round());
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
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
}
