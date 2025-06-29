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
    return SafeArea(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.background,
          elevation: 0,
          centerTitle: false,
          title: Text(
            'Folders',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        body: BlocBuilder<SyncedFoldersBloc, SyncedFoldersState>(
          builder: (context, state) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (state is SyncedFoldersLoaded) ...[
                      if (state.folders.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('No folders added yet', style: Theme.of(context).textTheme.bodyLarge),
                          ),
                        )
                      else ...[
                        ...state.folders.map((folder) => _buildFolderCard(context, folder)).toList(),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () => _addFolder(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Folder'),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        ),
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
                          context.read<SyncedFoldersBloc>().add(UpdateSyncedFolder(updatedFolder));
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
    final serverConfigBloc = context.read<ServerConfigBloc>();
    final state = serverConfigBloc.state;
    if (state is ServerConfigLoaded && state.config == null) {
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
                // Switch to settings tab (implement navigation if needed)
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
                    context.read<SyncedFoldersBloc>().add(AddSyncedFolder(newFolder));
                  } else {
                    context.read<SyncedFoldersBloc>().add(UpdateSyncedFolder(newFolder));
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
              context.read<SyncedFoldersBloc>().add(RemoveSyncedFolder(folder.id));
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

