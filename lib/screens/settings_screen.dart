import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync_bloc.dart';
import '../bloc/sync_event.dart';
import '../bloc/sync_state.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../services/settings_service.dart';
import '../services/file_sync_service.dart';

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
        title: const Text('Server Configuration'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  decoration: const InputDecoration(labelText: 'Hostname/IP'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter hostname';
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
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
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
                        decoration: const InputDecoration(labelText: 'Remote Path'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
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
                          
                          // Determine the initial browsing path based on server type and home directory
                          String initialPath = remotePathController.text.isEmpty ? '/' : remotePathController.text;
                          
                          // For SSH, try to detect home directory first if not already known
                          if (tempConfig.syncMode == SyncMode.ssh && tempConfig.homeDirectory == null) {
                            final detectionResult = await FileSyncService.testConnectionWithDetection(tempConfig);
                            if (detectionResult['success'] == true) {
                              if (detectionResult['serverType'] != null) {
                                detectedServerType = detectionResult['serverType'] as ServerType;
                              }
                              if (detectionResult['homeDirectory'] != null) {
                                final homeDir = detectionResult['homeDirectory'] as String;
                                tempConfig = tempConfig.copyWith(
                                  serverType: detectedServerType,
                                  homeDirectory: homeDir,
                                );
                                
                                // For Linux/Mac, default to home directory if no path is set
                                if ((detectedServerType == ServerType.linux || detectedServerType == ServerType.macos) && 
                                    remotePathController.text.isEmpty) {
                                  initialPath = homeDir;
                                  remotePathController.text = homeDir;
                                }
                              }
                            }
                          } else if (tempConfig.homeDirectory != null && 
                                   (tempConfig.serverType == ServerType.linux || tempConfig.serverType == ServerType.macos) &&
                                   remotePathController.text.isEmpty) {
                            // Use existing home directory if available
                            initialPath = tempConfig.homeDirectory!;
                            remotePathController.text = tempConfig.homeDirectory!;
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
    int selectedMinutes = config.intervalMinutes;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Interval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('15 minutes'),
              value: 15,
              groupValue: selectedMinutes,
              onChanged: (value) {
                if (value != null) selectedMinutes = value;
              },
            ),
            RadioListTile<int>(
              title: const Text('30 minutes'),
              value: 30,
              groupValue: selectedMinutes,
              onChanged: (value) {
                if (value != null) selectedMinutes = value;
              },
            ),
            RadioListTile<int>(
              title: const Text('1 hour'),
              value: 60,
              groupValue: selectedMinutes,
              onChanged: (value) {
                if (value != null) selectedMinutes = value;
              },
            ),
            RadioListTile<int>(
              title: const Text('2 hours'),
              value: 120,
              groupValue: selectedMinutes,
              onChanged: (value) {
                if (value != null) selectedMinutes = value;
              },
            ),
            RadioListTile<int>(
              title: const Text('6 hours'),
              value: 360,
              groupValue: selectedMinutes,
              onChanged: (value) {
                if (value != null) selectedMinutes = value;
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
              final newConfig = config.copyWith(intervalMinutes: selectedMinutes);
              context.read<SyncBloc>().add(SaveSchedulerConfig(newConfig));
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // On first connection, detect server type if not already detected
      if (!serverTypeDetected && widget.config.syncMode == SyncMode.ssh && widget.config.serverType == null) {
        final detectionResult = await FileSyncService.testConnectionWithDetection(widget.config);
        if (detectionResult['success'] == true && detectionResult['serverType'] != null) {
          final detectedType = detectionResult['serverType'] as ServerType;
          updatedConfig = widget.config.copyWith(serverType: detectedType);
          serverTypeDetected = true;
          
          // Show detection result to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🔍 Detected server type: ${detectedType.name.toUpperCase()}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
      
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
        height: 400,
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
            
            // Current path display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
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
                ],
              ),
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
}
