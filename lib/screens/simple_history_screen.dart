import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../bloc/sync_operation_bloc.dart';
import '../models/sync_record.dart';
import 'simple_settings_screen.dart';

class SimpleHistoryScreen extends StatefulWidget {
  final Future<String> Function(String) translate;

  const SimpleHistoryScreen({
    super.key,
    required this.translate,
  });

  @override
  State<SimpleHistoryScreen> createState() => _SimpleHistoryScreenState();
}

class _SimpleHistoryScreenState extends State<SimpleHistoryScreen> {
  final Set<String> _retryingFiles = <String>{};
  String _searchQuery = '';
  SyncStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: FutureBuilder<String>(
          future: widget.translate('Sync History'),
          builder: (context, snapshot) {
            return Text(
              snapshot.data ?? 'Sync History',
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search files',
            onPressed: _showSearchDialog,
          ),
          PopupMenuButton<SyncStatus?>(
            icon: Icon(
              Icons.filter_list,
              color: _statusFilter != null 
                ? Theme.of(context).colorScheme.primary 
                : null,
            ),
            tooltip: 'Filter by status',
            onSelected: (status) {
              setState(() {
                _statusFilter = status;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    Icon(
                      _statusFilter == null ? Icons.check : Icons.radio_button_unchecked,
                      size: 16,
                      color: _statusFilter == null ? Theme.of(context).colorScheme.primary : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: widget.translate('All'),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'All',
                          style: TextStyle(
                            fontWeight: _statusFilter == null ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SyncStatus.completed,
                child: Row(
                  children: [
                    Icon(
                      _statusFilter == SyncStatus.completed ? Icons.check : Icons.check_circle,
                      color: _statusFilter == SyncStatus.completed 
                        ? Theme.of(context).colorScheme.primary 
                        : Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: widget.translate('Completed'),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'Completed',
                          style: TextStyle(
                            fontWeight: _statusFilter == SyncStatus.completed ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SyncStatus.failed,
                child: Row(
                  children: [
                    Icon(
                      _statusFilter == SyncStatus.failed ? Icons.check : Icons.error,
                      color: _statusFilter == SyncStatus.failed 
                        ? Theme.of(context).colorScheme.primary 
                        : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: widget.translate('Failed'),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'Failed',
                          style: TextStyle(
                            fontWeight: _statusFilter == SyncStatus.failed ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SyncStatus.pending,
                child: Row(
                  children: [
                    Icon(
                      _statusFilter == SyncStatus.pending ? Icons.check : Icons.schedule,
                      color: _statusFilter == SyncStatus.pending 
                        ? Theme.of(context).colorScheme.primary 
                        : Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: widget.translate('Pending'),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? 'Pending',
                          style: TextStyle(
                            fontWeight: _statusFilter == SyncStatus.pending ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<SyncOperationBloc>().add(LoadSyncHistory());
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: BlocBuilder<SyncOperationBloc, SyncOperationState>(
          builder: (context, state) {
            if (state is SyncOperationLoaded) {
              var history = state.syncHistory;
              
              // Apply search filter
              if (_searchQuery.isNotEmpty) {
                history = history.where((record) =>
                  record.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  record.filePath.toLowerCase().contains(_searchQuery.toLowerCase())
                ).toList();
              }
              
              // Apply status filter
              if (_statusFilter != null) {
                history = history.where((record) => record.status == _statusFilter).toList();
              }
              
              if (history.isEmpty) {
                return _buildEmptyState();
              }

              // Group records by date
              final groupedHistory = _groupRecordsByDate(history);

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _calculateTotalItems(groupedHistory),
                itemBuilder: (context, index) {
                  return _buildGroupedItem(groupedHistory, index);
                },
              );
            }
            
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget _buildHistoryItem(SyncRecord record) {
    IconData icon;
    Color color;
    String statusText;
    Color statusBgColor;

    switch (record.status) {
      case SyncStatus.completed:
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        statusText = 'Synced';
        statusBgColor = Colors.green.withOpacity(0.1);
        break;
      case SyncStatus.failed:
        icon = Icons.error_rounded;
        color = Colors.red;
        statusText = 'Failed';
        statusBgColor = Colors.red.withOpacity(0.1);
        break;
      case SyncStatus.syncing:
        icon = Icons.sync_rounded;
        color = Colors.blue;
        statusText = 'Syncing';
        statusBgColor = Colors.blue.withOpacity(0.1);
        break;
      case SyncStatus.pending:
        icon = Icons.schedule_rounded;
        color = Colors.orange;
        statusText = 'Pending';
        statusBgColor = Colors.orange.withOpacity(0.1);
        break;
      case SyncStatus.skipped:
        icon = Icons.skip_next_rounded;
        color = Colors.grey;
        statusText = 'Skipped';
        statusBgColor = Colors.grey.withOpacity(0.1);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: record.status == SyncStatus.failed ? () => _showErrorDetails(record) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon with background
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fileName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _formatFileSize(record.fileSize),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTime(record.syncedAt ?? record.lastModified),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // Actions for failed items
              if (record.status == SyncStatus.failed) ...[
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      icon: _retryingFiles.contains(record.id)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      color: Colors.orange,
                      tooltip: 'Retry sync',
                      onPressed: _retryingFiles.contains(record.id)
                          ? null
                          : () => _retrySync(record),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.orange.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (record.status == SyncStatus.completed) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_rounded,
                  color: Colors.green,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildEmptyState() {
    final hasSearchOrFilter = _searchQuery.isNotEmpty || _statusFilter != null;
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearchOrFilter ? Icons.search_off_rounded : Icons.history_rounded,
                size: 60,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            FutureBuilder<String>(
              future: widget.translate(hasSearchOrFilter 
                  ? 'No matching files found'
                  : 'No sync history yet'),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? (hasSearchOrFilter 
                      ? 'No matching files found'
                      : 'No sync history yet'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                );
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<String>(
              future: widget.translate(hasSearchOrFilter
                  ? 'Try adjusting your search terms or filters'
                  : 'Files will appear here after your first sync'),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? (hasSearchOrFilter
                      ? 'Try adjusting your search terms or filters'
                      : 'Files will appear here after your first sync'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                );
              },
            ),
            if (hasSearchOrFilter) ...[
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.translate('Clear Filters'),
                builder: (context, snapshot) {
                  return OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _statusFilter = null;
                      });
                    },
                    icon: const Icon(Icons.clear_all_rounded),
                    label: Text(snapshot.data ?? 'Clear Filters'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.translate('Set Up Sync'),
                builder: (context, snapshot) {
                  return FilledButton.icon(
                    onPressed: () {
                      // Navigate directly to the Settings screen
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => SimpleSettingsScreen(
                            translate: widget.translate,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(snapshot.data ?? 'Set Up Sync'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: FutureBuilder<String>(
          future: widget.translate('Search Files'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Search Files');
          },
        ),
        content: FutureBuilder<String>(
          future: widget.translate('Enter file name or path...'),
          builder: (context, snapshot) {
            return TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: snapshot.data ?? 'Enter file name or path...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              controller: TextEditingController(text: _searchQuery),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.of(context).pop();
            },
            child: FutureBuilder<String>(
              future: widget.translate('Clear'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Clear');
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: FutureBuilder<String>(
              future: widget.translate('Done'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Done');
              },
            ),
          ),
        ],
      ),
    );
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FutureBuilder<String>(
                future: widget.translate('Sync Error Details'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'Sync Error Details');
                },
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildErrorDetailRow('File', record.fileName),
              const SizedBox(height: 12),
              _buildErrorDetailRow('Path', record.filePath),
              const SizedBox(height: 12),
              _buildErrorDetailRow('Size', _formatFileSize(record.fileSize)),
              const SizedBox(height: 12),
              _buildErrorDetailRow('Time', _formatDateTime(record.lastModified)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_rounded, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Error Message',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      record.errorMessage ?? "Unknown error occurred",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: widget.translate('You can retry this sync using the refresh button.'),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? 'You can retry this sync using the refresh button.',
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: FutureBuilder<String>(
              future: widget.translate('Close'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Close');
              },
            ),
          ),
          if (!_retryingFiles.contains(record.id))
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _retrySync(record);
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: FutureBuilder<String>(
                future: widget.translate('Retry Now'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'Retry Now');
                },
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  void _retrySync(SyncRecord record) {
    setState(() {
      _retryingFiles.add(record.id);
    });

    // Show a snackbar to give user feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FutureBuilder<String>(
          future: widget.translate('Retrying sync for ${record.fileName}...'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Retrying sync for ${record.fileName}...');
          },
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    // Trigger the retry through the BLoC
    context.read<SyncOperationBloc>().add(RetryFailedSync(record));

    // Remove from retrying set after some time (this will be updated when sync completes)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _retryingFiles.remove(record.id);
        });
      }
    });
  }

  // Group records by date for better organization
  Map<String, List<SyncRecord>> _groupRecordsByDate(List<SyncRecord> records) {
    // Use LinkedHashMap to preserve insertion order
    final Map<String, List<SyncRecord>> grouped = <String, List<SyncRecord>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: now.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    // Separate records by time periods
    final List<SyncRecord> todayRecords = [];
    final List<SyncRecord> yesterdayRecords = [];
    final List<SyncRecord> thisWeekRecords = [];
    final List<SyncRecord> thisMonthRecords = [];
    final Map<String, List<SyncRecord>> olderRecords = {};

    for (final record in records) {
      // Use syncedAt for completed records, lastModified for others
      final recordDate = record.syncedAt ?? record.lastModified;
      final recordDay = DateTime(recordDate.year, recordDate.month, recordDate.day);
      
      if (recordDay == today) {
        todayRecords.add(record);
      } else if (recordDay == yesterday) {
        yesterdayRecords.add(record);
      } else if (recordDay.isAfter(thisWeekStart.subtract(const Duration(days: 1)))) {
        thisWeekRecords.add(record);
      } else if (recordDay.isAfter(thisMonthStart.subtract(const Duration(days: 1)))) {
        thisMonthRecords.add(record);
      } else {
        // Format as "Month Year" for older records
        final formatter = DateFormat('MMMM yyyy');
        final groupKey = formatter.format(recordDate);
        if (!olderRecords.containsKey(groupKey)) {
          olderRecords[groupKey] = [];
        }
        olderRecords[groupKey]!.add(record);
      }
    }

    // Add groups in chronological order (newest first)
    if (todayRecords.isNotEmpty) {
      grouped['Today'] = todayRecords;
    }
    if (yesterdayRecords.isNotEmpty) {
      grouped['Yesterday'] = yesterdayRecords;
    }
    if (thisWeekRecords.isNotEmpty) {
      grouped['This Week'] = thisWeekRecords;
    }
    if (thisMonthRecords.isNotEmpty) {
      grouped['This Month'] = thisMonthRecords;
    }
    
    // Add older records in reverse chronological order
    final sortedOlderKeys = olderRecords.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMMM yyyy').parse(a);
        final dateB = DateFormat('MMMM yyyy').parse(b);
        return dateB.compareTo(dateA); // Newest first
      });
    
    for (final key in sortedOlderKeys) {
      grouped[key] = olderRecords[key]!;
    }

    return grouped;
  }

  // Calculate total items including headers
  int _calculateTotalItems(Map<String, List<SyncRecord>> groupedHistory) {
    int total = 0;
    for (final entry in groupedHistory.entries) {
      total += 1; // Header
      total += entry.value.length; // Records
    }
    return total;
  }

  // Build grouped items with headers
  Widget _buildGroupedItem(Map<String, List<SyncRecord>> groupedHistory, int index) {
    int currentIndex = 0;
    
    for (final entry in groupedHistory.entries) {
      // Check if this is a header
      if (currentIndex == index) {
        return _buildDateHeader(entry.key, entry.value);
      }
      currentIndex++;
      
      // Check if this is a record within this group
      final groupSize = entry.value.length;
      if (index < currentIndex + groupSize) {
        final recordIndex = index - currentIndex;
        return Padding(
          padding: const EdgeInsets.only(left: 0),
          child: _buildHistoryItem(entry.value[recordIndex]),
        );
      }
      currentIndex += groupSize;
    }
    
    return const SizedBox.shrink(); // Fallback
  }

  // Build date section header with statistics
  Widget _buildDateHeader(String title, List<SyncRecord> records) {
    final theme = Theme.of(context);
    final completed = records.where((r) => r.status == SyncStatus.completed).length;
    final failed = records.where((r) => r.status == SyncStatus.failed).length;
    final pending = records.where((r) => r.status == SyncStatus.pending).length;
    final total = records.length;
    
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$total file${total != 1 ? 's' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 24), // Align with title
                if (completed > 0) ...[
                  _buildStatChip(completed, 'synced', Colors.green, Icons.check_circle),
                  const SizedBox(width: 8),
                ],
                if (failed > 0) ...[
                  _buildStatChip(failed, 'failed', Colors.red, Icons.error),
                  const SizedBox(width: 8),
                ],
                if (pending > 0) ...[
                  _buildStatChip(pending, 'pending', Colors.orange, Icons.schedule),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(int count, String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}