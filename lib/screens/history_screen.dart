import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/sync_record.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              // Handle filter options
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All'),
              ),
              const PopupMenuItem(
                value: 'completed',
                child: Text('Completed'),
              ),
              const PopupMenuItem(
                value: 'failed',
                child: Text('Failed'),
              ),
            ],
            child: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: BlocBuilder<SyncBloc, SyncState>(
        builder: (context, state) {
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

          // For all other states, show history using FutureBuilder to get fresh data
          return FutureBuilder<List<SyncRecord>>(
            future: DatabaseService.getAllSyncRecords(),
            builder: (context, historySnapshot) {
              // Use data from state if available and fresh, otherwise use database data
              List<SyncRecord> syncHistory = [];
              
              if (state is SyncLoaded) {
                // Prefer state data when in SyncLoaded state as it's most current
                syncHistory = state.syncHistory;
              } else if (state is SyncInProgress) {
                // Use state data during sync for live updates
                syncHistory = state.syncHistory;
              } else if (historySnapshot.hasData) {
                // Use database data for other states (SyncSuccess, etc.)
                syncHistory = historySnapshot.data!;
              } else if (historySnapshot.connectionState == ConnectionState.waiting) {
                // Show loading while fetching from database
                return const Center(child: CircularProgressIndicator());
              }

              if (syncHistory.isEmpty) {
                return _buildEmptyState(context);
              }

              // Sort history by most recent first
              final sortedHistory = List<SyncRecord>.from(syncHistory)
                ..sort((a, b) {
                  final aTime = a.syncedAt ?? a.lastModified;
                  final bTime = b.syncedAt ?? b.lastModified;
                  return bTime.compareTo(aTime);
                });

              return Column(
                children: [
                  _buildStatsHeader(context, syncHistory, state),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: sortedHistory.length,
                      itemBuilder: (context, index) {
                        final record = sortedHistory[index];
                        return _buildHistoryCard(context, record);
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 120,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No sync history yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Your sync activity will appear here',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(BuildContext context, List<SyncRecord> history, SyncState state) {
    final completed = history.where((r) => r.status == SyncStatus.completed).length;
    final failed = history.where((r) => r.status == SyncStatus.failed).length;
    final pending = history.where((r) => r.status == SyncStatus.pending).length;

    return Container(
      margin: const EdgeInsets.all(16.0),
      child: Card(
        elevation: state is SyncInProgress ? 4 : 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'History Statistics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (state is SyncInProgress)
                    Container(
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
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Completed',
                      completed.toString(),
                      Colors.green,
                      Icons.check_circle,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Failed',
                      failed.toString(),
                      Colors.red,
                      Icons.error,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Pending',
                      pending.toString(),
                      Colors.orange,
                      Icons.pending,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context, SyncRecord record) {
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          record.fileName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [              Text(
                record.syncedAt != null
                    ? 'Synced: ${_formatDateTime(record.syncedAt!)}'
                    : 'Modified: ${_formatDateTime(record.lastModified)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    record.status.name.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatFileSize(record.fileSize),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(context, 'Path', record.filePath),
                const SizedBox(height: 8),
                _buildDetailRow(context, 'File Size', _formatFileSize(record.fileSize)),
                const SizedBox(height: 8),
                _buildDetailRow(context, 'Hash', record.hash.substring(0, 16) + '...'),
                const SizedBox(height: 8),
                _buildDetailRow(
                  context,
                  'Last Modified',
                  _formatDateTime(record.lastModified),
                ),
                if (record.syncedAt != null) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    context,
                    'Synced At',
                    _formatDateTime(record.syncedAt!),
                  ),
                ],
                if (record.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(context, 'Error', record.errorMessage!),
                ],
                if (record.deleted) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Text('File was auto-deleted after sync'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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
}
