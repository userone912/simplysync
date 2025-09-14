import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../models/sync_record.dart';

class SimpleHistoryScreen extends StatelessWidget {
  const SimpleHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Sync History'),
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
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
                    Icon(Icons.history, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No sync history yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Files will appear here after syncing',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final record = history[index];
                return _buildHistoryItem(record);
              },
            );
          }
          
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildHistoryItem(SyncRecord record) {
    IconData icon;
    Color color;
    String statusText;

    switch (record.status) {
      case SyncStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        statusText = 'Synced';
        break;
      case SyncStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        statusText = 'Failed';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Colors.blue;
        statusText = 'Syncing';
        break;
      case SyncStatus.pending:
        icon = Icons.schedule;
        color = Colors.orange;
        statusText = 'Pending';
        break;
      case SyncStatus.skipped:
        icon = Icons.skip_next;
        color = Colors.grey;
        statusText = 'Skipped';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          record.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_formatFileSize(record.fileSize)} • $statusText'),
            Text(
              _formatDateTime(record.syncedAt ?? record.lastModified),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: record.status == SyncStatus.failed
            ? Icon(Icons.info_outline, color: Colors.orange)
            : null,
        onTap: record.status == SyncStatus.failed
            ? () => _showErrorDetails(record)
            : null,
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  void _showErrorDetails(SyncRecord record) {
    // Would show error details in a dialog
    // Implementation depends on how error messages are stored
  }
}