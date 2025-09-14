import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../bloc/synced_folders_bloc.dart';
import '../models/synced_folder.dart';
import '../services/permission_service.dart';

class SimpleFoldersScreen extends StatefulWidget {
  final Future<String> Function(String) translate;

  const SimpleFoldersScreen({
    super.key,
    required this.translate,
  });

  @override
  State<SimpleFoldersScreen> createState() => _SimpleFoldersScreenState();
}

class _SimpleFoldersScreenState extends State<SimpleFoldersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: FutureBuilder<String>(
          future: widget.translate('Sync Folders'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Sync Folders');
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCustomFolder,
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
                  Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  FutureBuilder<String>(
                    future: widget.translate('Error: ${state.message}'),
                    builder: (context, snapshot) {
                      return Text(snapshot.data ?? 'Error: ${state.message}');
                    },
                  ),
                  ElevatedButton(
                    onPressed: () => context.read<SyncedFoldersBloc>().add(LoadSyncedFolders()),
                    child: FutureBuilder<String>(
                      future: widget.translate('Retry'),
                      builder: (context, snapshot) {
                        return Text(snapshot.data ?? 'Retry');
                      },
                    ),
                  ),
                ],
              ),
            );
          }

          final folders = state is SyncedFoldersLoaded ? state.folders : <SyncedFolder>[];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Media Folder Selection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<String>(
                          future: widget.translate('Common Media Folders'),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.data ?? 'Common Media Folders',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        FutureBuilder<String>(
                          future: widget.translate('Camera'),
                          builder: (context, snapshot) {
                            return _buildQuickFolderOption(
                              snapshot.data ?? 'Camera',
                              Icons.camera_alt,
                              () => _addCommonFolder('DCIM/Camera', 'Camera'),
                            );
                          },
                        ),
                        FutureBuilder<String>(
                          future: widget.translate('Downloads'),
                          builder: (context, snapshot) {
                            return _buildQuickFolderOption(
                              snapshot.data ?? 'Downloads',
                              Icons.download,
                              () => _addCommonFolder('Download', 'Downloads'),
                            );
                          },
                        ),
                        FutureBuilder<String>(
                          future: widget.translate('Pictures'),
                          builder: (context, snapshot) {
                            return _buildQuickFolderOption(
                              snapshot.data ?? 'Pictures',
                              Icons.image,
                              () => _addCommonFolder('Pictures', 'Pictures'),
                            );
                          },
                        ),
                        FutureBuilder<String>(
                          future: widget.translate('Documents'),
                          builder: (context, snapshot) {
                            return _buildQuickFolderOption(
                              snapshot.data ?? 'Documents',
                              Icons.description,
                              () => _addCommonFolder('Documents', 'Documents'),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Current Folders List
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              FutureBuilder<String>(
                                future: widget.translate('Synced Folders'),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? 'Synced Folders',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                              FutureBuilder<String>(
                                future: widget.translate('active'),
                                builder: (context, snapshot) {
                                  final activeText = snapshot.data ?? 'active';
                                  return Text(
                                    '${folders.where((f) => f.enabled).length}/${folders.length} $activeText',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          if (folders.isEmpty)
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                    const SizedBox(height: 16),
                                    FutureBuilder<String>(
                                      future: widget.translate('No folders added yet'),
                                      builder: (context, snapshot) {
                                        return Text(
                                          snapshot.data ?? 'No folders added yet',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    FutureBuilder<String>(
                                      future: widget.translate('Add folders above or use the + button'),
                                      builder: (context, snapshot) {
                                        return Text(
                                          snapshot.data ?? 'Add folders above or use the + button',
                                          style: TextStyle(color: Colors.grey[600]),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                itemCount: folders.length,
                                itemBuilder: (context, index) {
                                  final folder = folders[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Icon(
                                        _getFolderIcon(folder.name),
                                        color: folder.enabled ? Colors.blue : Colors.grey,
                                      ),
                                      title: Text(folder.name),
                                      subtitle: Text(
                                        folder.localPath,
                                        style: TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Switch(
                                            value: folder.enabled,
                                            onChanged: (value) {
                                              final updatedFolder = folder.copyWith(enabled: value);
                                              context.read<SyncedFoldersBloc>().add(
                                                UpdateSyncedFolder(updatedFolder),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _deleteFolder(context, folder),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickFolderOption(String name, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(name),
      trailing: const Icon(Icons.add_circle_outline),
      onTap: onTap,
    );
  }

  IconData _getFolderIcon(String folderName) {
    final name = folderName.toLowerCase();
    if (name.contains('camera') || name.contains('dcim')) return Icons.camera_alt;
    if (name.contains('download')) return Icons.download;
    if (name.contains('picture') || name.contains('image')) return Icons.image;
    if (name.contains('document')) return Icons.description;
    if (name.contains('music') || name.contains('audio')) return Icons.music_note;
    if (name.contains('video')) return Icons.video_library;
    return Icons.folder;
  }

  Future<void> _addCommonFolder(String relativePath, String displayName) async {
    try {
      // Request permissions first
      final hasPermission = await PermissionService.requestStoragePermission();
      if (!hasPermission) {
        _showPermissionError();
        return;
      }

      // Get external storage directory
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        _showError('Cannot access external storage');
        return;
      }

      // Construct full path
      String fullPath;
      if (relativePath == 'DCIM/Camera') {
        // Special case for camera folder
        fullPath = '/storage/emulated/0/DCIM/Camera';
      } else {
        fullPath = '/storage/emulated/0/$relativePath';
      }

      // Check if folder exists
      final folder = Directory(fullPath);
      if (!await folder.exists()) {
        _showError('Folder does not exist');
        return;
      }

      // Check if already added
      final state = context.read<SyncedFoldersBloc>().state;
      if (state is SyncedFoldersLoaded) {
        final exists = state.folders.any((f) => f.localPath == fullPath);
        if (exists) {
          _showError('Folder already added');
          return;
        }
      }

      // Add folder
      final syncedFolder = SyncedFolder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        localPath: fullPath,
        name: displayName,
        enabled: true,
      );

      context.read<SyncedFoldersBloc>().add(AddSyncedFolder(syncedFolder));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: FutureBuilder<String>(
            future: widget.translate('Added $displayName folder'),
            builder: (context, snapshot) {
              return Text(snapshot.data ?? 'Added $displayName folder');
            },
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Error adding folder');
    }
  }

  Future<void> _addCustomFolder() async {
    try {
      final hasPermission = await PermissionService.requestStoragePermission();
      if (!hasPermission) {
        _showPermissionError();
        return;
      }

      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        // Check if already added
        final state = context.read<SyncedFoldersBloc>().state;
        if (state is SyncedFoldersLoaded) {
          final exists = state.folders.any((f) => f.localPath == result);
          if (exists) {
            _showError('Folder already added');
            return;
          }
        }

        final folderName = result.split('/').last;
        final syncedFolder = SyncedFolder(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          localPath: result,
          name: folderName,
          enabled: true,
        );

        context.read<SyncedFoldersBloc>().add(AddSyncedFolder(syncedFolder));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: FutureBuilder<String>(
              future: widget.translate('Added $folderName folder'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Added $folderName folder');
              },
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Error selecting folder');
    }
  }

  void _deleteFolder(BuildContext context, SyncedFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: FutureBuilder<String>(
          future: widget.translate('Delete Folder'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Delete Folder');
          },
        ),
        content: FutureBuilder<String>(
          future: widget.translate('Remove "${folder.name}" from sync?'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Remove "${folder.name}" from sync?');
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: FutureBuilder<String>(
              future: widget.translate('Cancel'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Cancel');
              },
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<SyncedFoldersBloc>().add(RemoveSyncedFolder(folder.id));
              Navigator.of(context).pop();
            },
            child: FutureBuilder<String>(
              future: widget.translate('Delete'),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? 'Delete',
                  style: const TextStyle(color: Colors.red),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FutureBuilder<String>(
          future: widget.translate('Storage permission required to access folders'),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Storage permission required to access folders');
          },
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: FutureBuilder<String>(
          future: widget.translate(message),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? message);
          },
        ),
        backgroundColor: Colors.red,
      ),
    );
  }
}