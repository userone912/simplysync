import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/synced_folder.dart';
import '../services/permission_service.dart';
import '../services/database_service.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synced Folders'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: () => _addFolder(context),
            icon: const Icon(Icons.add),
            tooltip: 'Add Folder',
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

          // For all other states, show folders using FutureBuilder to get fresh data
          return FutureBuilder<List<SyncedFolder>>(
            future: DatabaseService.getAllSyncedFolders(),
            builder: (context, folderSnapshot) {
              // Use data from state if available and fresh, otherwise use database data
              List<SyncedFolder> syncedFolders = [];
              
              if (state is SyncLoaded) {
                // Prefer state data when in SyncLoaded state as it's most current
                syncedFolders = state.syncedFolders;
              } else if (folderSnapshot.hasData) {
                // Use database data for other states (SyncInProgress, SyncSuccess, etc.)
                syncedFolders = folderSnapshot.data!;
              } else if (folderSnapshot.connectionState == ConnectionState.waiting) {
                // Show loading while fetching from database
                return const Center(child: CircularProgressIndicator());
              }

              if (syncedFolders.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: syncedFolders.length,
                itemBuilder: (context, index) {
                  final folder = syncedFolders[index];
                  return _buildFolderCard(context, folder);
                },
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
            Icons.folder_open,
            size: 120,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No folders added yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Add folders to start syncing your files',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _addFolder(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Folder'),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(BuildContext context, SyncedFolder folder) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder,
                  color: folder.enabled 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        folder.localPath,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editFolder(context, folder);
                        break;
                      case 'delete':
                        _deleteFolder(context, folder);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit),
                        title: Text('Edit'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete),
                        title: Text('Delete'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Switch(
                        value: folder.enabled,
                        onChanged: (value) {
                          final updatedFolder = folder.copyWith(enabled: value);
                          context.read<SyncBloc>().add(UpdateSyncedFolder(updatedFolder));
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        folder.enabled ? 'Enabled' : 'Disabled',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.auto_delete,
                      size: 16,
                      color: folder.autoDelete 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      folder.autoDelete ? 'Auto-delete' : 'Keep files',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addFolder(BuildContext context) async {
    // First check if server is configured
    final syncBloc = context.read<SyncBloc>();
    final state = syncBloc.state;
    
    if (state is SyncLoaded && state.serverConfig == null) {
      // Show dialog suggesting to configure server first
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚙️ Server Configuration Required'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You need to configure your server connection before adding folders to sync.'),
              SizedBox(height: 12),
              Text(
                'Steps to get started:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('1. Go to Settings'),
              Text('2. Configure your server connection'),
              Text('3. Test the connection'),
              Text('4. Return here to add folders'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Switch to settings tab (assuming this is called from a parent that manages tabs)
                // You might need to implement navigation to settings here
              },
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      );
      return;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    
    if (result != null) {
      // Check if the app has write permission to this directory
      final hasWritePermission = await PermissionService.canWriteToDirectory(result);
      
      if (!hasWritePermission) {
        // Show permission warning dialog
        final continueAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Write Permission Warning'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'simplySync cannot write to this directory. This may cause sync failures.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    result,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Common causes:\n'
                  '• System or protected directory\n'
                  '• External storage without permission\n'
                  '• Directory owned by another app\n'
                  '\n'
                  'Try selecting a folder in your Documents, Downloads, or Pictures directory.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        );

        if (continueAnyway != true) {
          return;
        }
      }

      _showFolderDialog(context, localPath: result);
    }
  }

  void _editFolder(BuildContext context, SyncedFolder folder) {
    _showFolderDialog(
      context,
      folder: folder,
      localPath: folder.localPath,
    );
  }

  void _showFolderDialog(
    BuildContext context, {
    SyncedFolder? folder,
    required String localPath,
  }) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: folder?.name ?? localPath.split('/').last,
    );
    bool enabled = folder?.enabled ?? true;
    bool autoDelete = folder?.autoDelete ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(folder == null ? 'Add Folder' : 'Edit Folder'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Folder Name',
                    helperText: 'A friendly name for this folder',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a folder name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Path',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        localPath,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enabled'),
                  subtitle: const Text('Include this folder in sync'),
                  value: enabled,
                  onChanged: (value) {
                    setState(() {
                      enabled = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Auto Delete'),
                  subtitle: const Text('Delete files after successful sync'),
                  value: autoDelete,
                  onChanged: (value) {
                    setState(() {
                      autoDelete = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final newFolder = SyncedFolder(
                    id: folder?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    localPath: localPath,
                    name: nameController.text,
                    enabled: enabled,
                    autoDelete: autoDelete,
                  );

                  if (folder == null) {
                    context.read<SyncBloc>().add(AddSyncedFolder(newFolder));
                  } else {
                    context.read<SyncBloc>().add(UpdateSyncedFolder(newFolder));
                  }

                  Navigator.of(context).pop();
                }
              },
              child: Text(folder == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteFolder(BuildContext context, SyncedFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to remove "${folder.name}" from sync?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<SyncBloc>().add(RemoveSyncedFolder(folder.id));
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
