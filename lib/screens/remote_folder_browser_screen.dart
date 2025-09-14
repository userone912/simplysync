import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../models/remote_item.dart';
import '../services/file_sync_service.dart';

class RemoteFolderBrowserScreen extends StatefulWidget {
  final ServerConfig serverConfig;
  final String? initialPath;

  const RemoteFolderBrowserScreen({
    super.key,
    required this.serverConfig,
    this.initialPath,
  });

  @override
  State<RemoteFolderBrowserScreen> createState() => _RemoteFolderBrowserScreenState();
}

class _RemoteFolderBrowserScreenState extends State<RemoteFolderBrowserScreen> {
  List<RemoteItem> _items = [];
  bool _isLoading = false;
  String _currentPath = '/';
  List<String> _pathHistory = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? widget.serverConfig.remotePath;
    _loadDirectory();
  }

  Future<void> _loadDirectory([String? path]) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final targetPath = path ?? _currentPath;
      final items = await FileSyncService.listRemoteDirectory(widget.serverConfig, targetPath);
      
      setState(() {
        _items = items;
        _currentPath = targetPath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load directory: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateToFolder(RemoteItem folder) {
    if (folder.isFolder) {
      _pathHistory.add(_currentPath);
      _loadDirectory(folder.path);
    }
  }

  void _navigateUp() {
    if (_pathHistory.isNotEmpty) {
      final previousPath = _pathHistory.removeLast();
      _loadDirectory(previousPath);
    } else {
      // Try to navigate to parent directory
      final parts = _currentPath.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        parts.removeLast();
        final parentPath = parts.isEmpty ? '/' : '/${parts.join('/')}/';
        _pathHistory.add(_currentPath);
        _loadDirectory(parentPath);
      }
    }
  }

  void _selectCurrentPath() {
    Navigator.of(context).pop(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Remote Folder'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selectCurrentPath,
            tooltip: 'Select this folder',
          ),
        ],
      ),
      body: Column(
        children: [
          // Current path display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Row(
              children: [
                if (_pathHistory.isNotEmpty || _currentPath != '/')
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _navigateUp,
                    tooltip: 'Go back',
                  ),
                Expanded(
                  child: Text(
                    _currentPath.isEmpty ? '/' : _currentPath,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _loadDirectory(),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Directory contents
          Expanded(
            child: _buildDirectoryContents(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _selectCurrentPath,
        label: const Text('Select This Folder'),
        icon: const Icon(Icons.check),
      ),
    );
  }

  Widget _buildDirectoryContents() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading directory...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadDirectory(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('This folder is empty'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return _buildItemTile(item);
      },
    );
  }

  Widget _buildItemTile(RemoteItem item) {
    return ListTile(
      leading: Icon(
        item.isFolder ? Icons.folder : Icons.insert_drive_file,
        color: item.isFolder ? Colors.blue : Colors.grey,
      ),
      title: Text(item.name),
      subtitle: item.isFile && item.size != null
          ? Text(_formatFileSize(item.size!))
          : item.lastModified != null
              ? Text(_formatDateTime(item.lastModified!))
              : null,
      onTap: item.isFolder ? () => _navigateToFolder(item) : null,
      trailing: item.isFolder ? const Icon(Icons.chevron_right) : null,
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}