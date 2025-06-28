import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/settings_service.dart';
import '../services/file_sync_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../utils/logger.dart' as app_logger;

class FolderBrowserResult {
  final String? selectedPath;
  final ServerConfig? updatedConfig;
  
  const FolderBrowserResult({
    this.selectedPath,
    this.updatedConfig,
  });
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                    'Error loading settings',
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

          // For all other states, show settings using FutureBuilder to get fresh data
          return FutureBuilder<ServerConfig?>(
            future: SettingsService.getServerConfig(),
            builder: (context, serverSnapshot) {
              return FutureBuilder<SchedulerConfig>(
                future: SettingsService.getSchedulerConfig(),
                builder: (context, schedulerSnapshot) {
                  return FutureBuilder<bool>(
                    future: SettingsService.getAutoDeleteEnabled(),
                    builder: (context, autoDeleteSnapshot) {
                      // Use data from state if available, otherwise use fresh data from services
                      ServerConfig? serverConfig = serverSnapshot.data;
                      SchedulerConfig schedulerConfig = schedulerSnapshot.data ?? const SchedulerConfig();
                      bool autoDeleteEnabled = autoDeleteSnapshot.data ?? false;
                      bool permissionsGranted = false;
                      
                      if (state is SyncLoaded) {
                        // Prefer state data when available as it's more current
                        serverConfig = state.serverConfig ?? serverConfig;
                        schedulerConfig = state.schedulerConfig;
                        autoDeleteEnabled = state.autoDeleteEnabled;
                        permissionsGranted = state.permissionsGranted;
                      }

                      return ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _buildServerConfigCard(serverConfig),
                          const SizedBox(height: 16),
                          _buildSchedulerConfigCard(schedulerConfig),
                          const SizedBox(height: 16),
                          _buildGeneralSettingsCard(autoDeleteEnabled, permissionsGranted),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildServerConfigCard(ServerConfig? serverConfig) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server Configuration',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (serverConfig != null) ...[
              ListTile(
                leading: Icon(
                  serverConfig.syncMode == SyncMode.ssh ? Icons.terminal : Icons.cloud,
                ),
                title: Text(serverConfig.syncMode.name.toUpperCase()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${serverConfig.hostname}:${serverConfig.port}'),
                    if (serverConfig.serverType != null)
                      Text(
                        'Server: ${serverConfig.serverType!.name.toUpperCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                trailing: const Icon(Icons.edit),
                onTap: () => _showServerConfigDialog(serverConfig),
              ),
            ] else ...[
              const ListTile(
                leading: Icon(Icons.warning),
                title: Text('No server configured'),
                subtitle: Text('Tap to configure your server'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _showServerConfigDialog(null),
                child: const Text('Configure Server'),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulerConfigCard(SchedulerConfig schedulerConfig) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scheduler Settings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto Sync'),
              subtitle: const Text('Enable automatic file synchronization'),
              value: schedulerConfig.enabled,
              onChanged: (value) {
                final newConfig = schedulerConfig.copyWith(enabled: value);
                context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
              },
            ),
            if (schedulerConfig.enabled) ...[
              SwitchListTile(
                title: const Text('Daily Sync'),
                subtitle: const Text('Sync once daily at a specific time'),
                value: schedulerConfig.isDailySync,
                onChanged: (value) {
                  final newConfig = schedulerConfig.copyWith(isDailySync: value);
                  context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
                },
              ),
              if (schedulerConfig.isDailySync)
                ListTile(
                  title: const Text('Daily Sync Time'),
                  subtitle: Text(_formatTime(schedulerConfig.dailySyncHour, schedulerConfig.dailySyncMinute)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _showTimePickerDialog(schedulerConfig),
                )
              else
                ListTile(
                  title: const Text('Sync Interval'),
                  subtitle: Text('${schedulerConfig.intervalMinutes} minutes'),
                  trailing: const Icon(Icons.timer),
                  onTap: () => _showIntervalDialog(schedulerConfig),
                ),
              SwitchListTile(
                title: const Text('WiFi Only'),
                subtitle: const Text('Sync only when connected to WiFi'),
                value: schedulerConfig.syncOnlyOnWifi,
                onChanged: (value) {
                  final newConfig = schedulerConfig.copyWith(syncOnlyOnWifi: value);
                  context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
                },
              ),
              SwitchListTile(
                title: const Text('Charging Only'),
                subtitle: const Text('Sync only when device is charging'),
                value: schedulerConfig.syncOnlyWhenCharging,
                onChanged: (value) {
                  final newConfig = schedulerConfig.copyWith(syncOnlyWhenCharging: value);
                  context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsCard(bool autoDeleteEnabled, bool permissionsGranted) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'General Settings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto Delete'),
              subtitle: const Text('Delete files after successful sync'),
              value: autoDeleteEnabled,
              onChanged: (value) {
                context.read<SyncBloc>().add(SetAutoDelete(value));
              },
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Permissions'),
              subtitle: Text(
                permissionsGranted ? 'All permissions granted' : 'Some permissions missing',
              ),
              trailing: Icon(
                permissionsGranted ? Icons.check_circle : Icons.warning,
                color: permissionsGranted ? Colors.green : Colors.orange,
              ),
              onTap: () {
                if (!permissionsGranted) {
                  context.read<SyncBloc>().add(RequestPermissions());
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Test Notifications'),
              subtitle: const Text('Send a test notification to verify setup'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showTestNotification(),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('Delete Synced Files'),
              subtitle: const Text('Remove successfully synced files from device'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showDeleteSyncedFilesDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _showServerConfigDialog(ServerConfig? existingConfig) {
    final formKey = GlobalKey<FormState>();
    SyncMode syncMode = existingConfig?.syncMode ?? SyncMode.ssh;
    final hostnameController = TextEditingController(text: existingConfig?.hostname ?? '');
    final portController = TextEditingController(text: existingConfig?.port.toString() ?? '22');
    final usernameController = TextEditingController(text: existingConfig?.username ?? '');
    final passwordController = TextEditingController(text: existingConfig?.password ?? '');
    final remotePathController = TextEditingController(text: existingConfig?.remotePath ?? '/');
    ServerType? detectedServerType = existingConfig?.serverType;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingConfig == null ? 'Add Server Configuration' : 'Edit Server Configuration'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existingConfig == null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Configure your server connection details. Make sure your server is accessible and you have the correct credentials.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<SyncMode>(
                  value: syncMode,
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  items: SyncMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      syncMode = value;
                      portController.text = value == SyncMode.ssh ? '22' : '21';
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: hostnameController,
                  decoration: const InputDecoration(
                    labelText: 'Hostname/IP Address',
                    hintText: 'e.g., 192.168.1.100 or myserver.com',
                    helperText: 'The IP address or domain name of your server',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter hostname or IP address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: portController,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter port';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Please enter valid port (1-65535)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'Your server login username',
                    helperText: 'The username for your server account',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'Your server login password',
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: remotePathController,
                        decoration: const InputDecoration(
                          labelText: 'Remote Path',
                          hintText: '/home/user/sync or /path/to/folder',
                          helperText: 'The server directory where files will be synced',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter remote path';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        // Create a temporary config to test with current form values
                        if (hostnameController.text.isNotEmpty &&
                            usernameController.text.isNotEmpty &&
                            passwordController.text.isNotEmpty) {
                          var tempConfig = ServerConfig(
                            syncMode: syncMode,
                            hostname: hostnameController.text,
                            port: int.tryParse(portController.text) ?? (syncMode == SyncMode.ssh ? 22 : 21),
                            username: usernameController.text,
                            password: passwordController.text,
                            remotePath: remotePathController.text.isEmpty ? '/' : remotePathController.text,
                          );
                          
                          // Determine the intelligent browsing path based on server type
                          String initialPath = remotePathController.text;
                          
                          // Get the smart default directory for this server configuration
                          if (initialPath.isEmpty) {
                            initialPath = await FileSyncService.getDefaultBrowsingDirectory(tempConfig);
                            if (initialPath != '/' && initialPath.isNotEmpty) {
                              // Pre-fill the remote path field with the detected home directory
                              remotePathController.text = initialPath;
                            }
                          }
                          
                          final result = await _showFolderBrowser(context, tempConfig, initialPath);
                          if (result?.selectedPath != null) {
                            remotePathController.text = result!.selectedPath!;
                            // Update detected server info if it was detected during browsing
                            if (result.updatedConfig?.serverType != null) {
                              detectedServerType = result.updatedConfig!.serverType;
                            }
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill in server details first'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Browse folders',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                // Additional validation for edge cases
                final hostname = hostnameController.text.trim();
                final username = usernameController.text.trim();
                final password = passwordController.text;
                final remotePath = remotePathController.text.trim();
                final port = int.tryParse(portController.text.trim());

                // Validate hostname format
                if (hostname.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Hostname cannot be empty'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Validate port
                if (port == null || port < 1 || port > 65535) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Port must be between 1 and 65535'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Validate credentials
                if (username.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Username and password are required'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Validate remote path
                if (remotePath.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Remote path cannot be empty'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // For SSH servers, try to detect server info if not already detected
                ServerType? finalServerType = detectedServerType;
                String? finalHomeDirectory;
                
                if (syncMode == SyncMode.ssh && detectedServerType == null) {
                  final tempConfig = ServerConfig(
                    syncMode: syncMode,
                    hostname: hostnameController.text,
                    port: int.parse(portController.text),
                    username: usernameController.text,
                    password: passwordController.text,
                    remotePath: remotePathController.text,
                  );
                  
                  final detectionResult = await FileSyncService.testConnectionWithDetection(tempConfig);
                  if (detectionResult['success'] == true) {
                    finalServerType = detectionResult['serverType'] as ServerType?;
                    finalHomeDirectory = detectionResult['homeDirectory'] as String?;
                  }
                }
                
                final config = ServerConfig(
                  syncMode: syncMode,
                  hostname: hostnameController.text,
                  port: int.parse(portController.text),
                  username: usernameController.text,
                  password: passwordController.text,
                  remotePath: remotePathController.text,
                  serverType: finalServerType,
                  homeDirectory: finalHomeDirectory,
                );
                
                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('💾 Server configuration saved successfully!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
                
                context.read<SyncBloc>().add(SaveServerConfig(config));
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showIntervalDialog(SchedulerConfig config) {
    showDialog(
      context: context,
      builder: (context) => _IntervalPickerDialog(config: config),
    );
  }

  String _formatTime(int hour, int minute) {
    // Convert 24-hour format to 12-hour format with AM/PM
    final isPM = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    final period = isPM ? 'PM' : 'AM';
    return '$displayHour:$minuteStr $period';
  }

  void _showTimePickerDialog(SchedulerConfig config) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: config.dailySyncHour, minute: config.dailySyncMinute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      final newConfig = config.copyWith(
        dailySyncHour: pickedTime.hour,
        dailySyncMinute: pickedTime.minute,
      );
      context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
    }
  }

  Future<FolderBrowserResult?> _showFolderBrowser(BuildContext context, ServerConfig config, String currentPath) async {
    return showDialog<FolderBrowserResult>(
      context: context,
      builder: (context) => _FolderBrowserDialog(
        config: config,
        initialPath: currentPath,
      ),
    );
  }

  void _showTestNotification() async {
    try {
      await NotificationService.showSyncStarted();
      await Future.delayed(const Duration(seconds: 1));
      await NotificationService.showSyncProgress(
        currentFile: 1,
        totalFiles: 3,
        fileName: 'test_document.pdf',
      );
      await Future.delayed(const Duration(seconds: 2));
      await NotificationService.showSyncCompleted(
        syncedCount: 3,
        errorCount: 0,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Test notifications sent! Check your notification panel.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to send test notification: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showDeleteSyncedFilesDialog() async {
    // First, get count of synced files to show to user
    final syncedFiles = await DatabaseService.getSyncRecordsByStatus(SyncStatus.completed);
    final syncedCount = syncedFiles.length;
    
    if (syncedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No synced files found to delete'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Delete Synced Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently delete $syncedCount successfully synced files from your device.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Make sure files are safely backed up on your server before deleting!',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('This action cannot be undone.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performDeleteSyncedFiles(syncedFiles);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete Files'),
          ),
        ],
      ),
    );
  }

  void _performDeleteSyncedFiles(List<SyncRecord> syncedFiles) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Deleting Files...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Deleting ${syncedFiles.length} synced files...'),
          ],
        ),
      ),
    );

    int deletedCount = 0;
    int errorCount = 0;
    List<String> errors = [];

    try {
      for (final record in syncedFiles) {
        try {
          final file = File(record.filePath);
          if (await file.exists()) {
            await file.delete();
            
            // Mark the record as deleted in database
            final updatedRecord = record.copyWith(deleted: true);
            await DatabaseService.updateSyncRecord(updatedRecord);
            
            deletedCount++;
            app_logger.Logger.info('Deleted synced file: ${record.filePath}');
          } else {
            // File doesn't exist anymore, just mark as deleted in database
            final updatedRecord = record.copyWith(deleted: true);
            await DatabaseService.updateSyncRecord(updatedRecord);
            deletedCount++;
          }
        } catch (e) {
          errorCount++;
          errors.add('${record.fileName}: $e');
          app_logger.Logger.error('Failed to delete file: ${record.filePath}', error: e);
        }
      }
    } finally {
      // Close the progress dialog
      Navigator.of(context).pop();
    }

    // Show result dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(errorCount == 0 ? '✅ Deletion Complete' : '⚠️ Deletion Complete with Errors'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully deleted: $deletedCount files'),
            if (errorCount > 0) ...[
              const SizedBox(height: 8),
              Text('Failed to delete: $errorCount files'),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Errors:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(
                      errors.take(5).join('\n'), // Show first 5 errors
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                if (errors.length > 5)
                  Text('... and ${errors.length - 5} more errors'),
              ],
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Show summary snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errorCount == 0 
              ? '✅ Deleted $deletedCount synced files' 
              : '⚠️ Deleted $deletedCount files, $errorCount failed',
        ),
        backgroundColor: errorCount == 0 ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _FolderBrowserDialog extends StatefulWidget {
  final ServerConfig config;
  final String initialPath;

  const _FolderBrowserDialog({
    required this.config,
    required this.initialPath,
  });

  @override
  State<_FolderBrowserDialog> createState() => _FolderBrowserDialogState();
}

class _FolderBrowserDialogState extends State<_FolderBrowserDialog> {
  String currentPath = '/';
  List<String> directories = [];
  bool isLoading = false;
  String? error;
  bool serverTypeDetected = false;
  ServerConfig? updatedConfig;

  @override
  void initState() {
    super.initState();
    currentPath = widget.initialPath;
    updatedConfig = widget.config;
    _initializeOptimalStartingDirectory();
  }

  Future<void> _initializeOptimalStartingDirectory() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // For SSH servers, detect server info and get optimal starting directory
      if (widget.config.syncMode == SyncMode.ssh) {
        final detectionResult = await FileSyncService.testConnectionWithDetection(widget.config);
        if (detectionResult['success'] == true) {
          final detectedType = detectionResult['serverType'] as ServerType?;
          final detectedHome = detectionResult['homeDirectory'] as String?;
          
          if (detectedType != null) {
            updatedConfig = widget.config.copyWith(
              serverType: detectedType,
              homeDirectory: detectedHome,
            );
            serverTypeDetected = true;
            
            // For Linux/Mac, automatically use home directory instead of root
            if ((detectedType == ServerType.linux || detectedType == ServerType.macos) && 
                detectedHome != null && 
                (currentPath == '/' || currentPath.isEmpty)) {
              currentPath = detectedHome;
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🏠 Starting from home directory: $detectedHome'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🔍 Detected server: ${detectedType.name.toUpperCase()}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        }
      }
      
      // Now load directories from the determined starting path
      await _loadDirectories();
      
    } catch (e) {
      setState(() {
        error = 'Failed to initialize browser: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _loadDirectories() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final dirs = await FileSyncService.listDirectories(updatedConfig!, currentPath);
      setState(() {
        directories = dirs;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to load directories: $e';
        isLoading = false;
      });
    }
  }

  void _navigateToDirectory(String path) {
    // For Linux/Mac SSH servers, warn if trying to navigate outside home directory
    if (updatedConfig?.syncMode == SyncMode.ssh && 
        updatedConfig?.homeDirectory != null && 
        (updatedConfig?.serverType == ServerType.linux || updatedConfig?.serverType == ServerType.macos)) {
      
      final homeDir = updatedConfig!.homeDirectory!;
      
      // Check if the target path is outside the home directory
      if (!path.startsWith(homeDir) && path != homeDir) {
        // Show warning dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Permission Warning'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You\'re trying to navigate outside your home directory:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    homeDir,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'On Linux/Mac servers, you typically only have write permissions in your home directory and its subdirectories. '
                  'Accessing other directories may result in permission errors during sync.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 Recommended locations:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text('• ~/Documents/'),
                      Text('• ~/Pictures/'),
                      Text('• ~/Downloads/'),
                      Text('• Create a new folder in your home directory'),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    currentPath = path;
                  });
                  _loadDirectories();
                },
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        );
        return;
      }
    }
    
    setState(() {
      currentPath = path;
    });
    _loadDirectories();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Browse Server Folders'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6, // Use 60% of screen height
        child: Column(
          children: [
            // Permission info banner for Linux/Mac SSH servers
            if (updatedConfig?.syncMode == SyncMode.ssh && 
                (updatedConfig?.serverType == ServerType.linux || updatedConfig?.serverType == ServerType.macos))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        updatedConfig?.homeDirectory != null
                            ? 'Tip: Stay within your home directory (${updatedConfig!.homeDirectory}) for write permissions'
                            : 'Tip: Choose a folder within your home directory for write permissions',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Current path display with server info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentPath,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Show if this is the home directory
                      if (updatedConfig?.homeDirectory != null && 
                          currentPath == updatedConfig!.homeDirectory)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'HOME',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Show server info and permission hints
                  if (updatedConfig != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          updatedConfig!.syncMode == SyncMode.ssh ? Icons.terminal : Icons.cloud,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${updatedConfig!.syncMode.name.toUpperCase()}${updatedConfig!.serverType != null ? ' • ${updatedConfig!.serverType!.name.toUpperCase()}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    // Permission hint for SSH servers
                    if (updatedConfig!.syncMode == SyncMode.ssh && 
                        updatedConfig!.homeDirectory != null && 
                        (updatedConfig!.serverType == ServerType.linux || 
                         updatedConfig!.serverType == ServerType.macos)) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            currentPath.startsWith(updatedConfig!.homeDirectory!) 
                                ? Icons.check_circle 
                                : Icons.warning,
                            size: 14,
                            color: currentPath.startsWith(updatedConfig!.homeDirectory!) 
                                ? Colors.green 
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              currentPath.startsWith(updatedConfig!.homeDirectory!) 
                                  ? 'You have write permissions here'
                                  : 'Limited permissions outside home directory',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: currentPath.startsWith(updatedConfig!.homeDirectory!) 
                                    ? Colors.green 
                                    : Colors.orange,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Action buttons row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _showCreateFolderDialog,
                    icon: const Icon(Icons.create_new_folder),
                    label: const Text('New Folder'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : _loadDirectories,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Directory list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadDirectories,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : directories.isEmpty
                          ? const Center(
                              child: Text('No directories found'),
                            )
                          : ListView.builder(
                              itemCount: directories.length,
                              itemBuilder: (context, index) {
                                final directory = directories[index];
                                final isParent = index == 0 && currentPath != '/' && currentPath.isNotEmpty;
                                
                                return ListTile(
                                  leading: Icon(
                                    isParent ? Icons.arrow_upward : Icons.folder,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  title: Text(
                                    isParent 
                                        ? '.. (Parent Directory)'
                                        : directory.split('/').last.isEmpty 
                                            ? '/'
                                            : directory.split('/').last,
                                  ),
                                  subtitle: isParent ? null : Text(directory),
                                  onTap: () => _navigateToDirectory(directory),
                                );
                              },
                            ),
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
          onPressed: () => Navigator.of(context).pop(
            FolderBrowserResult(
              selectedPath: currentPath,
              updatedConfig: serverTypeDetected ? updatedConfig : null,
            ),
          ),
          child: const Text('Select'),
        ),
      ],
    );
  }

  void _showCreateFolderDialog() {
    final TextEditingController folderNameController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create a new folder in:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  currentPath,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: folderNameController,
                decoration: const InputDecoration(
                  labelText: 'Folder Name',
                  hintText: 'Enter folder name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a folder name';
                  }
                  if (value.contains('/') || value.contains('\\')) {
                    return 'Folder name cannot contain / or \\';
                  }
                  if (value.trim() == '.' || value.trim() == '..') {
                    return 'Invalid folder name';
                  }
                  return null;
                },
                autofocus: true,
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
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop();
                await _createFolder(folderNameController.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(String folderName) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // Normalize the path - ensure it doesn't end with multiple slashes
      String normalizedCurrentPath = currentPath;
      if (normalizedCurrentPath.endsWith('/') && normalizedCurrentPath != '/') {
        normalizedCurrentPath = normalizedCurrentPath.substring(0, normalizedCurrentPath.length - 1);
      }
      
      final newFolderPath = '$normalizedCurrentPath/$folderName';
      app_logger.Logger.info('Creating folder: $newFolderPath from current path: $currentPath');

      // The createDirectory method now throws exceptions on failure, returns true on success
      await FileSyncService.createDirectory(updatedConfig!, newFolderPath);
      
      // If we reach here, the directory was created successfully
      app_logger.Logger.info('✅ Folder created successfully: $newFolderPath');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Folder "$folderName" created successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Refresh the directory listing
      await _loadDirectories();
      
    } catch (e) {
      final errorMsg = e.toString();
      app_logger.Logger.error('Failed to create folder: $folderName', error: e);
      setState(() {
        error = 'Failed to create folder: $errorMsg';
        isLoading = false;
      });
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to create folder: $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

class _IntervalPickerDialog extends StatefulWidget {
  final SchedulerConfig config;

  const _IntervalPickerDialog({required this.config});

  @override
  State<_IntervalPickerDialog> createState() => _IntervalPickerDialogState();
}

class _IntervalPickerDialogState extends State<_IntervalPickerDialog> {
  late int selectedMinutes;

  @override
  void initState() {
    super.initState();
    selectedMinutes = widget.config.intervalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync Interval'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<int>(
            title: const Text('15 minutes'),
            value: 15,
            groupValue: selectedMinutes,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedMinutes = value;
                });
              }
            },
          ),
          RadioListTile<int>(
            title: const Text('30 minutes'),
            value: 30,
            groupValue: selectedMinutes,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedMinutes = value;
                });
              }
            },
          ),
          RadioListTile<int>(
            title: const Text('1 hour'),
            value: 60,
            groupValue: selectedMinutes,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedMinutes = value;
                });
              }
            },
          ),
          RadioListTile<int>(
            title: const Text('2 hours'),
            value: 120,
            groupValue: selectedMinutes,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedMinutes = value;
                });
              }
            },
          ),
          RadioListTile<int>(
            title: const Text('6 hours'),
            value: 360,
            groupValue: selectedMinutes,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedMinutes = value;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final newConfig = widget.config.copyWith(intervalMinutes: selectedMinutes);
            context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}