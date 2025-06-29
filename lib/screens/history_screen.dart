import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../models/sync_record.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: () {
              context.read<SyncOperationBloc>().add(LoadSyncHistory());
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<SyncOperationBloc, SyncOperationState>(
        builder: (context, state) {
          if (state is SyncOperationLoaded) {
            final history = state.syncHistory;
            
            if (history.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No sync history yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Start syncing to see history here',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }
            
            return Column(
              children: [
                _buildStatsHeader(context, history),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final record = history[index];
                      return _buildHistoryItem(context, record);
                    },
                  ),
                ),
              ],
            );
          }
          
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildStatsHeader(BuildContext context, List<SyncRecord> history) {
    final completedCount = history.where((r) => r.status == SyncStatus.completed).length;
    final failedCount = history.where((r) => r.status == SyncStatus.failed).length;
    final totalSize = history.fold<int>(0, (sum, record) => sum + record.fileSize);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatColumn(
              label: 'Total',
              value: '${history.length}',
              color: Colors.blue,
            ),
          ),
          Expanded(
            child: _StatColumn(
              label: 'Completed',
              value: '$completedCount',
              color: Colors.green,
            ),
          ),
          Expanded(
            child: _StatColumn(
              label: 'Failed',
              value: '$failedCount',
              color: Colors.red,
            ),
          ),
          Expanded(
            child: _StatColumn(
              label: 'Total Size',
              value: _formatFileSize(totalSize),
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, SyncRecord record) {
    IconData icon;
    Color statusColor;
    
    switch (record.status) {
      case SyncStatus.completed:
        icon = Icons.check_circle;
        statusColor = Colors.green;
        break;
      case SyncStatus.failed:
        icon = Icons.error;
        statusColor = Colors.red;
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        statusColor = Colors.blue;
        break;
      case SyncStatus.pending:
        icon = Icons.schedule;
        statusColor = Colors.orange;
        break;
      case SyncStatus.skipped:
        icon = Icons.skip_next;
        statusColor = Colors.grey;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: statusColor),
        title: Text(
          record.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.filePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _formatFileSize(record.fileSize),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                if (record.syncedAt != null)
                  Text(
                    _formatDate(record.syncedAt!),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
        trailing: record.status == SyncStatus.failed && record.errorMessage != null
          ? IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showErrorDialog(context, record),
            )
          : null,
      ),
    );
  }

  void _showErrorDialog(BuildContext context, SyncRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${record.fileName}'),
            const SizedBox(height: 8),
            Text('Error: ${record.errorMessage}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
