import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../bloc/synced_folders_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../bloc/app_bloc_provider.dart';
import '../models/synced_folder.dart';
import '../services/permission_service.dart';

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
      body: BlocBuilder<SyncedFoldersBloc, SyncedFoldersState>(
        builder: (context, state) {
          if (state is SyncedFoldersLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (state is SyncedFoldersError) {
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
                    'Error loading folders',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.syncedFoldersBloc.add(LoadSyncedFolders()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          if (state is SyncedFoldersLoaded) {
            if (state.folders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No folders configured',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add a folder to start syncing your files',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _addFolder(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Folder'),
                    ),
                  ],
                ),
              );
            }
            
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.folders.length,
              itemBuilder: (context, index) {
                final folder = state.folders[index];
                return _buildFolderCard(context, folder);
              },
            );
          }
          
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildFolderCard(BuildContext context, SyncedFolder folder) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder,
                  color: folder.enabled ? Colors.blue : Colors.grey,
                  size: 24,
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
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: folder.enabled,
                  onChanged: (enabled) {
                    final updatedFolder = folder.copyWith(enabled: enabled);
                    context.syncedFoldersBloc.add(UpdateSyncedFolder(updatedFolder));
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDelete(context, folder);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (folder.autoDelete) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Auto-delete after sync',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip(
                  folder.enabled ? 'Enabled' : 'Disabled',
                  folder.enabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  folder.autoDelete ? 'Auto-delete' : 'Keep files',
                  folder.autoDelete ? Colors.orange : Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    // Check server configuration first
    final serverConfigState = context.read<ServerConfigBloc>().state;
    if (serverConfigState is! ServerConfigLoaded || serverConfigState.config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure server settings first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check permissions
    final hasPermission = await PermissionService.hasStoragePermission();
    if (!hasPermission) {
      final granted = await PermissionService.requestStoragePermission();
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to select folders'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Select folder
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;

    if (context.mounted) {
      _showFolderConfigDialog(context, selectedDirectory);
    }
  }

  void _showFolderConfigDialog(BuildContext context, String localPath) {
    final nameController = TextEditingController(
      text: localPath.split('/').last,
    );
    bool autoDelete = false;
    bool enabled = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Configure Folder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Folder Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: autoDelete,
                      onChanged: (value) {
                        setState(() {
                          autoDelete = value ?? false;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text('Auto-delete files after sync'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value ?? true;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text('Enable sync'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a folder name'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final newFolder = SyncedFolder(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  localPath: localPath,
                  enabled: enabled,
                  autoDelete: autoDelete,
                );

                context.syncedFoldersBloc.add(AddSyncedFolder(newFolder));
                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Folder "${newFolder.name}" added successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SyncedFolder folder) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Are you sure you want to remove "${folder.name}" from sync? This will not delete the actual folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.syncedFoldersBloc.add(RemoveSyncedFolder(folder.id));
              Navigator.of(dialogContext).pop();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Folder "${folder.name}" removed'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
