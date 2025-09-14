import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import '../bloc/app_settings_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/database_service.dart';
import 'remote_folder_browser_screen.dart';

class SimpleSettingsScreen extends StatefulWidget {
  final Future<String> Function(String) translate;

  const SimpleSettingsScreen({
    super.key,
    required this.translate,
  });

  @override
  State<SimpleSettingsScreen> createState() => _SimpleSettingsScreenState();
}

class _SimpleSettingsScreenState extends State<SimpleSettingsScreen> {
  final _hostnameController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remotePathController = TextEditingController();
  final _bearerTokenController = TextEditingController();
  final _baseUrlController = TextEditingController();
  
  SyncMode _selectedProtocol = SyncMode.ftp;
  bool _autoSyncEnabled = false;
  SyncScheduleType _scheduleType = SyncScheduleType.interval;
  int _syncIntervalMinutes = 60;
  int _syncHour = 9;
  int _syncMinute = 0;
  int _weekDay = 1; // Monday
  bool _wifiOnlySync = true;
  bool _chargingOnlySync = false;
  bool _useSSL = false;
  AuthType _authType = AuthType.password;
  bool _autoDeleteEnabled = false;

  @override
  void initState() {
    super.initState();
    
    // Add listeners to connection fields to update browse button state
    _hostnameController.addListener(_updateButtonState);
    _usernameController.addListener(_updateButtonState);
    _passwordController.addListener(_updateButtonState);
    
    // Trigger loading of settings
    context.read<ServerConfigBloc>().add(LoadServerConfig());
    context.read<AppSettingsBloc>().add(LoadAppSettings());
    
    // Unfocus any active text fields when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).unfocus();
    });
  }

  void _updateButtonState() {
    setState(() {
      // This will trigger a rebuild and update the browse button state
    });
  }

  @override
  void dispose() {
    // Remove listeners before disposing controllers
    _hostnameController.removeListener(_updateButtonState);
    _usernameController.removeListener(_updateButtonState);
    _passwordController.removeListener(_updateButtonState);
    
    _hostnameController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    _bearerTokenController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ServerConfigBloc, ServerConfigState>(
          listener: (context, state) {
            if (state is ServerConfigLoaded && state.config != null) {
              final config = state.config!;
              _hostnameController.text = config.hostname;
              _portController.text = config.port.toString();
              _usernameController.text = config.username;
              _passwordController.text = config.password;
              _remotePathController.text = config.remotePath;
              _bearerTokenController.text = config.bearerToken ?? '';
              _baseUrlController.text = config.baseUrl ?? '';
              setState(() {
                _selectedProtocol = config.syncMode;
                _useSSL = config.useSSL;
                _authType = config.authType;
              });
            }
          },
        ),
        BlocListener<AppSettingsBloc, AppSettingsState>(
          listener: (context, state) {
            if (state is AppSettingsLoaded) {
              setState(() {
                _autoSyncEnabled = state.schedulerConfig.enabled;
                _scheduleType = state.schedulerConfig.scheduleType;
                _syncIntervalMinutes = state.schedulerConfig.intervalMinutes;
                _syncHour = state.schedulerConfig.syncHour;
                _syncMinute = state.schedulerConfig.syncMinute;
                _weekDay = state.schedulerConfig.weekDay;
                _wifiOnlySync = state.schedulerConfig.syncOnlyOnWifi;
                _chargingOnlySync = state.schedulerConfig.syncOnlyWhenCharging;
                _autoDeleteEnabled = state.autoDeleteEnabled;
              });
            }
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          title: FutureBuilder<String>(
            future: widget.translate('Settings'),
            builder: (context, snapshot) {
              return Text(snapshot.data ?? 'Settings');
            },
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
          elevation: 0,
        ),
        body: GestureDetector(
          onTap: () {
            // Dismiss keyboard when tapping outside text fields
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    // Server Configuration
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<String>(
                            future: widget.translate('Server Configuration'),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? 'Server Configuration',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Protocol Selection
                          FutureBuilder<String>(
                            future: widget.translate('Protocol'),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? 'Protocol',
                                style: Theme.of(context).textTheme.titleMedium,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<SyncMode>(
                            segments: [
                              ButtonSegment(value: SyncMode.ftp, label: FutureBuilder<String>(
                                future: widget.translate('FTP'),
                                builder: (context, snapshot) => Text(snapshot.data ?? 'FTP'),
                              )),
                              ButtonSegment(value: SyncMode.ssh, label: FutureBuilder<String>(
                                future: widget.translate('SSH'),
                                builder: (context, snapshot) => Text(snapshot.data ?? 'SSH'),
                              )),
                              ButtonSegment(value: SyncMode.webdav, label: FutureBuilder<String>(
                                future: widget.translate('WebDAV'),
                                builder: (context, snapshot) => Text(snapshot.data ?? 'WebDAV'),
                              )),
                            ],
                            selected: {_selectedProtocol},
                            onSelectionChanged: (Set<SyncMode> selection) {
                              setState(() {
                                _selectedProtocol = selection.first;
                                // Set default ports
                                switch (_selectedProtocol) {
                                  case SyncMode.ftp:
                                    _portController.text = '21';
                                    break;
                                  case SyncMode.ssh:
                                    _portController.text = '22';
                                    break;
                                  case SyncMode.webdav:
                                    _portController.text = '80';
                                    break;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          // Server Details - different UI for WebDAV
                          if (_selectedProtocol == SyncMode.webdav) ...[
                            FutureBuilder<String>(
                              future: widget.translate('WebDAV URL'),
                              builder: (context, snapshot) {
                                return TextField(
                                  controller: _baseUrlController,
                                  decoration: InputDecoration(
                                    labelText: snapshot.data ?? 'WebDAV URL',
                                    hintText: 'https://cloud.example.com/remote.php/dav/files/username/',
                                    border: const OutlineInputBorder(),
                                  ),
                                );
                              },
                            ),
                          ] else ...[
                            FutureBuilder<String>(
                              future: widget.translate('Server Address'),
                              builder: (context, snapshot) {
                                return TextField(
                                  controller: _hostnameController,
                                  decoration: InputDecoration(
                                    labelText: snapshot.data ?? 'Server Address',
                                    hintText: 'e.g., 192.168.1.100 or myserver.com',
                                    border: const OutlineInputBorder(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            
                            FutureBuilder<String>(
                              future: widget.translate('Port'),
                              builder: (context, snapshot) {
                                return TextField(
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: snapshot.data ?? 'Port',
                                    border: const OutlineInputBorder(),
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          
                          FutureBuilder<String>(
                            future: widget.translate('User Login'),
                            builder: (context, snapshot) {
                              return TextField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  labelText: snapshot.data ?? 'User Login',
                                  border: const OutlineInputBorder(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          FutureBuilder<String>(
                            future: widget.translate('Password'),
                            builder: (context, snapshot) {
                              return TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: snapshot.data ?? 'Password',
                                  border: const OutlineInputBorder(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),

                          // Protocol-specific options
                          if (_selectedProtocol == SyncMode.ftp || _selectedProtocol == SyncMode.webdav) ...[
                            Row(
                              children: [
                                Checkbox(
                                  value: _useSSL,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _useSSL = value ?? false;
                                      // Update default port based on SSL setting
                                      if (_selectedProtocol == SyncMode.ftp) {
                                        _portController.text = _useSSL ? '990' : '21';
                                      } else if (_selectedProtocol == SyncMode.webdav) {
                                        _portController.text = _useSSL ? '443' : '80';
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: FutureBuilder<String>(
                                    future: _selectedProtocol == SyncMode.ftp 
                                        ? widget.translate('Use FTPS (SSL/TLS)') 
                                        : widget.translate('Use HTTPS'),
                                    builder: (context, snapshot) {
                                      return Text(
                                        snapshot.data ?? (_selectedProtocol == SyncMode.ftp 
                                            ? 'Use FTPS (SSL/TLS)' 
                                            : 'Use HTTPS'),
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (_selectedProtocol == SyncMode.webdav) ...[
                            DropdownButtonFormField<AuthType>(
                              value: _authType,
                              decoration: const InputDecoration(
                                labelText: 'Authentication', // Will be handled by individual translation calls
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: AuthType.password,
                                  child: FutureBuilder<String>(
                                    future: widget.translate('Username/Password'),
                                    builder: (context, snapshot) {
                                      return Text(snapshot.data ?? 'Username/Password');
                                    },
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: AuthType.token,
                                  child: FutureBuilder<String>(
                                    future: widget.translate('Bearer Token'),
                                    builder: (context, snapshot) {
                                      return Text(snapshot.data ?? 'Bearer Token');
                                    },
                                  ),
                                ),
                              ],
                              onChanged: (AuthType? value) {
                                setState(() {
                                  _authType = value ?? AuthType.password;
                                });
                              },
                            ),
                            const SizedBox(height: 12),

                            if (_authType == AuthType.token) ...[
                              FutureBuilder<String>(
                                future: widget.translate('Bearer Token'),
                                builder: (context, snapshot) {
                                  return TextField(
                                    controller: _bearerTokenController,
                                    decoration: InputDecoration(
                                      labelText: snapshot.data ?? 'Bearer Token',
                                      hintText: 'Enter your access token',
                                      border: const OutlineInputBorder(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                          
                          // Remote Path Selection - moved to end of server config
                          Row(
                            children: [
                              Expanded(
                                child: FutureBuilder<String>(
                                  future: widget.translate('Remote Path'),
                                  builder: (context, snapshot) {
                                    return TextField(
                                      controller: _remotePathController,
                                      decoration: InputDecoration(
                                        labelText: snapshot.data ?? 'Remote Path',
                                        hintText: '/',
                                        border: const OutlineInputBorder(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _canBrowseRemoteFolders() ? _browseRemoteFolder : null,
                                icon: const Icon(Icons.folder_open),
                                tooltip: 'Browse server folders',
                                style: IconButton.styleFrom(
                                  backgroundColor: _canBrowseRemoteFolders() 
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Auto Sync Configuration
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<String>(
                            future: widget.translate('Auto Sync'),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? 'Auto Sync',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          SwitchListTile(
                            title: FutureBuilder<String>(
                              future: widget.translate('Enable Auto Sync'),
                              builder: (context, snapshot) {
                                return Text(snapshot.data ?? 'Enable Auto Sync');
                              },
                            ),
                            subtitle: FutureBuilder<String>(
                              future: widget.translate('Automatically sync files in background'),
                              builder: (context, snapshot) {
                                return Text(snapshot.data ?? 'Automatically sync files in background');
                              },
                            ),
                            value: _autoSyncEnabled,
                            onChanged: (value) {
                              setState(() => _autoSyncEnabled = value);
                            },
                          ),
                          
                          if (_autoSyncEnabled) ...[
                            const SizedBox(height: 16),
                            
                            // Schedule Type Selection
                            FutureBuilder<String>(
                              future: widget.translate('Schedule Type'),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? 'Schedule Type', 
                                  style: Theme.of(context).textTheme.titleMedium,
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<SyncScheduleType>(
                              segments: [
                                ButtonSegment(
                                  value: SyncScheduleType.interval, 
                                  label: FutureBuilder<String>(
                                    future: widget.translate('Interval'),
                                    builder: (context, snapshot) => Text(snapshot.data ?? 'Interval'),
                                  ),
                                  tooltip: 'Sync every few minutes/hours',
                                ),
                                ButtonSegment(
                                  value: SyncScheduleType.daily, 
                                  label: FutureBuilder<String>(
                                    future: widget.translate('Daily'),
                                    builder: (context, snapshot) => Text(snapshot.data ?? 'Daily'),
                                  ),
                                  tooltip: 'Sync once per day at specific time',
                                ),
                                ButtonSegment(
                                  value: SyncScheduleType.weekly, 
                                  label: FutureBuilder<String>(
                                    future: widget.translate('Weekly'),
                                    builder: (context, snapshot) => Text(snapshot.data ?? 'Weekly'),
                                  ),
                                  tooltip: 'Sync once per week on specific day/time',
                                ),
                              ],
                              selected: {_scheduleType},
                              onSelectionChanged: (Set<SyncScheduleType> selection) {
                                setState(() {
                                  _scheduleType = selection.first;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Schedule Configuration based on type
                            if (_scheduleType == SyncScheduleType.interval) ...[
                              FutureBuilder<String>(
                                future: widget.translate('Sync Interval'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Sync Interval', style: Theme.of(context).textTheme.titleMedium);
                                },
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: _syncIntervalMinutes.toDouble(),
                                min: 15,
                                max: 360, // 6 hours max for interval
                                divisions: 23,
                                label: _syncIntervalMinutes < 60 
                                    ? '$_syncIntervalMinutes min'
                                    : '${(_syncIntervalMinutes / 60).toStringAsFixed(1)} hr',
                                onChanged: (value) {
                                  setState(() => _syncIntervalMinutes = value.round());
                                },
                              ),
                              FutureBuilder<String>(
                                future: _syncIntervalMinutes < 60 
                                    ? widget.translate('Sync every $_syncIntervalMinutes minutes')
                                    : widget.translate('Sync every ${(_syncIntervalMinutes / 60).toStringAsFixed(1)} hours'),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? 'Sync every ${_syncIntervalMinutes < 60 ? '$_syncIntervalMinutes minutes' : '${(_syncIntervalMinutes / 60).toStringAsFixed(1)} hours'}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    textAlign: TextAlign.center,
                                  );
                                },
                              ),
                            ] else if (_scheduleType == SyncScheduleType.daily) ...[
                              FutureBuilder<String>(
                                future: widget.translate('Daily Sync Time'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Daily Sync Time', style: Theme.of(context).textTheme.titleMedium);
                                },
                              ),
                              const SizedBox(height: 8),
                              Card(
                                child: ListTile(
                                  leading: const Icon(Icons.schedule),
                                  title: FutureBuilder<String>(
                                    future: widget.translate('Sync Time'),
                                    builder: (context, snapshot) {
                                      return Text(snapshot.data ?? 'Sync Time');
                                    },
                                  ),
                                  subtitle: Text('${_syncHour.toString().padLeft(2, '0')}:${_syncMinute.toString().padLeft(2, '0')}'),
                                  trailing: const Icon(Icons.edit),
                                  onTap: () => _showTimePicker(context),
                                ),
                              ),
                            ] else if (_scheduleType == SyncScheduleType.weekly) ...[
                              FutureBuilder<String>(
                                future: widget.translate('Weekly Sync Schedule'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Weekly Sync Schedule', style: Theme.of(context).textTheme.titleMedium);
                                },
                              ),
                              const SizedBox(height: 8),
                              Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.calendar_today),
                                      title: FutureBuilder<String>(
                                        future: widget.translate('Day of Week'),
                                        builder: (context, snapshot) {
                                          return Text(snapshot.data ?? 'Day of Week');
                                        },
                                      ),
                                      subtitle: Text(_getWeekdayName(_weekDay)),
                                      trailing: const Icon(Icons.edit),
                                      onTap: () => _showWeekdayPicker(context),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.schedule),
                                      title: FutureBuilder<String>(
                                        future: widget.translate('Sync Time'),
                                        builder: (context, snapshot) {
                                          return Text(snapshot.data ?? 'Sync Time');
                                        },
                                      ),
                                      subtitle: Text('${_syncHour.toString().padLeft(2, '0')}:${_syncMinute.toString().padLeft(2, '0')}'),
                                      trailing: const Icon(Icons.edit),
                                      onTap: () => _showTimePicker(context),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 16),
                            
                            SwitchListTile(
                              title: FutureBuilder<String>(
                                future: widget.translate('WiFi Only'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'WiFi Only');
                                },
                              ),
                              subtitle: FutureBuilder<String>(
                                future: widget.translate('Only sync when connected to WiFi'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Only sync when connected to WiFi');
                                },
                              ),
                              value: _wifiOnlySync,
                              onChanged: (value) {
                                setState(() => _wifiOnlySync = value);
                              },
                            ),
                            
                            SwitchListTile(
                              title: FutureBuilder<String>(
                                future: widget.translate('Charging Only'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Charging Only');
                                },
                              ),
                              subtitle: FutureBuilder<String>(
                                future: widget.translate('Only sync when device is charging'),
                                builder: (context, snapshot) {
                                  return Text(snapshot.data ?? 'Only sync when device is charging');
                                },
                              ),
                              value: _chargingOnlySync,
                              onChanged: (value) {
                                setState(() => _chargingOnlySync = value);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Auto Delete Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              FutureBuilder<String>(
                                future: widget.translate('Auto Delete Files'),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? 'Auto Delete Files',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.dangerous, color: Colors.red, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FutureBuilder<String>(
                                        future: widget.translate('WARNING: This will PERMANENTLY DELETE local files after sync!'),
                                        builder: (context, snapshot) {
                                          return Text(
                                            snapshot.data ?? 'WARNING: This will PERMANENTLY DELETE local files after sync!',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FutureBuilder<String>(
                                  future: widget.translate('• Files will be deleted from your device immediately after successful sync\n• This action cannot be undone\n• Only enable if you want to move (not copy) files to the server\n• Make sure your sync is working perfectly before enabling this'),
                                  builder: (context, snapshot) {
                                    return Text(
                                      snapshot.data ?? '• Files will be deleted from your device immediately after successful sync\n'
                                      '• This action cannot be undone\n'
                                      '• Only enable if you want to move (not copy) files to the server\n'
                                      '• Make sure your sync is working perfectly before enabling this',
                                      style: const TextStyle(fontSize: 12),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          SwitchListTile(
                            title: FutureBuilder<String>(
                              future: widget.translate('Delete Local Files After Sync'),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? 'Delete Local Files After Sync',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                );
                              },
                            ),
                            subtitle: FutureBuilder<String>(
                              future: widget.translate('Files will be permanently deleted from device after successful upload'),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? 'Files will be permanently deleted from device after successful upload',
                                  style: const TextStyle(fontSize: 12),
                                );
                              },
                            ),
                            value: _autoDeleteEnabled,
                            activeColor: Colors.red,
                            onChanged: (value) {
                              if (value) {
                                // Show additional confirmation dialog for enabling
                                _showAutoDeleteConfirmationDialog(context, value);
                              } else {
                                // Allow disabling without confirmation
                                setState(() => _autoDeleteEnabled = value);
                                context.read<AppSettingsBloc>().add(SetAutoDelete(value));
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          // Manual Delete Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _showManualDeleteConfirmationDialog(context),
                              icon: Icon(
                                Icons.delete_sweep,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              label: FutureBuilder<String>(
                                future: widget.translate('Delete Synced Files Now'),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? 'Delete Synced Files Now',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Theme.of(context).colorScheme.error,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<String>(
                            future: widget.translate('Manually delete synced files from device to free up storage space'),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? 'Manually delete synced files from device to free up storage space',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: FutureBuilder<String>(
                  future: widget.translate('Save Settings'),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? 'Save Settings',
                      style: const TextStyle(fontSize: 16),
                    );
                  },
                ),
              ),
            ),
          ], // Close Column children
        ), // Close Padding
        ), // Close GestureDetector
      ),
    ), // Close Scaffold
    ); // Close MultiBlocListener
  }

  void _saveSettings() {
    // Save server configuration
    final hasValidConnection = _selectedProtocol == SyncMode.webdav
        ? _baseUrlController.text.isNotEmpty
        : _hostnameController.text.isNotEmpty;
    
    final hasValidCredentials = _usernameController.text.isNotEmpty && 
        (_authType == AuthType.password ? _passwordController.text.isNotEmpty : 
         _authType == AuthType.token ? _bearerTokenController.text.isNotEmpty : false);
    
    if (hasValidConnection && hasValidCredentials) {
      
      // Extract hostname from baseUrl for WebDAV
      String hostname = _hostnameController.text;
      if (_selectedProtocol == SyncMode.webdav && _baseUrlController.text.isNotEmpty) {
        try {
          final uri = Uri.parse(_baseUrlController.text);
          hostname = uri.host;
        } catch (e) {
          hostname = 'webdav-server'; // fallback
        }
      }
      
      final serverConfig = ServerConfig(
        syncMode: _selectedProtocol,
        hostname: hostname,
        port: int.tryParse(_portController.text) ?? 
              (_selectedProtocol == SyncMode.ssh ? 22 : 
               _selectedProtocol == SyncMode.ftp ? 21 : 80),
        username: _usernameController.text,
        password: _passwordController.text,
        remotePath: _remotePathController.text.isEmpty ? '/' : _remotePathController.text,
        useSSL: _useSSL,
        authType: _authType,
        bearerToken: _authType == AuthType.token ? _bearerTokenController.text : null,
        baseUrl: _selectedProtocol == SyncMode.webdav ? _baseUrlController.text : null,
      );
      
      context.read<ServerConfigBloc>().add(SaveServerConfig(serverConfig));
    }

    // Save scheduler configuration
    final schedulerConfig = SchedulerConfig(
      enabled: _autoSyncEnabled,
      scheduleType: _scheduleType,
      intervalMinutes: _syncIntervalMinutes,
      syncHour: _syncHour,
      syncMinute: _syncMinute,
      weekDay: _weekDay,
      syncOnlyOnWifi: _wifiOnlySync,
      syncOnlyWhenCharging: _chargingOnlySync,
    );
    
    context.read<AppSettingsBloc>().add(SaveSchedulerConfig(schedulerConfig));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  bool _canBrowseRemoteFolders() {
    // Can browse if we have minimum connection info
    if (_selectedProtocol == SyncMode.webdav) {
      return _baseUrlController.text.isNotEmpty &&
             _usernameController.text.isNotEmpty &&
             (_authType == AuthType.password ? _passwordController.text.isNotEmpty : 
              _authType == AuthType.token ? _bearerTokenController.text.isNotEmpty : false);
    } else {
      return _hostnameController.text.isNotEmpty &&
             _usernameController.text.isNotEmpty &&
             _passwordController.text.isNotEmpty;
    }
  }

  Future<void> _browseRemoteFolder() async {
    if (!_canBrowseRemoteFolders()) return;

    try {
      // Extract hostname from baseUrl for WebDAV
      String hostname = _hostnameController.text;
      if (_selectedProtocol == SyncMode.webdav && _baseUrlController.text.isNotEmpty) {
        try {
          final uri = Uri.parse(_baseUrlController.text);
          hostname = uri.host;
        } catch (e) {
          hostname = 'webdav-server'; // fallback
        }
      }
      
      // Create a temporary server config for browsing
      final tempConfig = ServerConfig(
        syncMode: _selectedProtocol,
        hostname: hostname,
        port: int.tryParse(_portController.text) ?? 
              (_selectedProtocol == SyncMode.ssh ? 22 : 
               _selectedProtocol == SyncMode.ftp ? 21 : 80),
        username: _usernameController.text,
        password: _passwordController.text,
        remotePath: _remotePathController.text.isEmpty ? '/' : _remotePathController.text,
        useSSL: _useSSL,
        authType: _authType,
        bearerToken: _authType == AuthType.token ? _bearerTokenController.text : null,
        baseUrl: _selectedProtocol == SyncMode.webdav ? _baseUrlController.text : null,
      );

      // Open the remote folder browser
      final selectedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => RemoteFolderBrowserScreen(
            serverConfig: tempConfig,
            initialPath: _remotePathController.text.isEmpty ? '/' : _remotePathController.text,
            translate: widget.translate,
          ),
        ),
      );

      // Update the text field if a path was selected
      if (selectedPath != null) {
        _remotePathController.text = selectedPath;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to browse remote folders: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAutoDeleteConfirmationDialog(BuildContext context, bool value) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force user to make a choice
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.dangerous, color: Colors.red),
            const SizedBox(width: 8),
            const Text('DANGEROUS SETTING'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you absolutely sure you want to enable auto-delete?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text('This will:'),
            const SizedBox(height: 8),
            const Text('• PERMANENTLY DELETE files from your device after sync'),
            const Text('• Cannot be undone once files are deleted'),
            const Text('• Only files that sync successfully will be deleted'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Text(
                'ONLY ENABLE THIS IF:\n'
                '✓ Your sync is working perfectly\n'
                '✓ You want to MOVE (not copy) files to server\n'
                '✓ You have tested sync thoroughly',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Don't change the setting
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _autoDeleteEnabled = value);
              context.read<AppSettingsBloc>().add(SetAutoDelete(value));
              
              // Show additional warning
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '⚠️ Auto-delete enabled! Files will be deleted after sync.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('I Understand - Enable'),
          ),
        ],
      ),
    );
  }

  String _getWeekdayName(int weekday) {
    const weekdays = [
      '', // 0 is not used
      'Monday',
      'Tuesday', 
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[weekday];
  }

  Future<void> _showTimePicker(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _syncHour, minute: _syncMinute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _syncHour = picked.hour;
        _syncMinute = picked.minute;
      });
    }
  }

  Future<void> _showWeekdayPicker(BuildContext context) async {
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday', 
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Day of Week'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: weekdays.asMap().entries.map((entry) {
            final index = entry.key + 1; // 1-7 for Monday-Sunday
            final name = entry.value;
            return RadioListTile<int>(
              title: Text(name),
              value: index,
              groupValue: _weekDay,
              onChanged: (value) {
                setState(() {
                  _weekDay = value!;
                });
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showManualDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning, color: Colors.red, size: 48),
        title: FutureBuilder<String>(
          future: widget.translate('Delete Synced Files?'),
          builder: (context, snapshot) {
            return Text(
              snapshot.data ?? 'Delete Synced Files?',
              style: const TextStyle(color: Colors.red),
            );
          },
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: widget.translate('This will permanently delete synced files from your device to free up storage space.'),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? 'This will permanently delete synced files from your device to free up storage space.',
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ Important:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<String>(
                    future: widget.translate('• Only files with successful sync records will be deleted\n• Files that failed to sync will be kept\n• This action cannot be undone\n• Make sure your files are safely stored on the server'),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? '• Only files with successful sync records will be deleted\n'
                            '• Files that failed to sync will be kept\n'
                            '• This action cannot be undone\n'
                            '• Make sure your files are safely stored on the server',
                        style: const TextStyle(fontSize: 13),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
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
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performManualDelete(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: FutureBuilder<String>(
              future: widget.translate('Delete Files'),
              builder: (context, snapshot) {
                return Text(snapshot.data ?? 'Delete Files');
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performManualDelete(BuildContext context) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              FutureBuilder<String>(
                future: widget.translate('Deleting synced files...'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'Deleting synced files...');
                },
              ),
            ],
          ),
        ),
      );

      // Get successfully synced files from database
      final syncedRecords = await DatabaseService.getSyncRecordsByStatus(SyncStatus.completed);
      
      int deletedCount = 0;
      int failedCount = 0;
      
      // Delete only files that were successfully synced
      for (final record in syncedRecords) {
        if (record.filePath.isNotEmpty) {
          try {
            final file = File(record.filePath);
            if (await file.exists()) {
              await file.delete();
              deletedCount++;
              
              // Remove the record from database since file is deleted
              await DatabaseService.deleteSyncRecord(record.id);
            }
          } catch (e) {
            failedCount++;
            // Log the error but continue with other files
            print('Failed to delete ${record.filePath}: $e');
          }
        }
      }

      // Check if widget is still mounted before using context
      if (!mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      // Show result dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            deletedCount > 0 ? Icons.check_circle : Icons.info,
            color: deletedCount > 0 ? Colors.green : Colors.blue,
            size: 48,
          ),
          title: FutureBuilder<String>(
            future: widget.translate('Cleanup Complete'),
            builder: (context, snapshot) {
              return Text(snapshot.data ?? 'Cleanup Complete');
            },
          ),
          content: FutureBuilder<String>(
            future: widget.translate('Deleted $deletedCount files successfully.${failedCount > 0 ? '\nFailed to delete $failedCount files.' : ''}'),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? 'Deleted $deletedCount files successfully.${failedCount > 0 ? '\nFailed to delete $failedCount files.' : ''}',
              );
            },
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: FutureBuilder<String>(
                future: widget.translate('OK'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'OK');
                },
              ),
            ),
          ],
        ),
      );

    } catch (e) {
      // Check if widget is still mounted before using context
      if (!mounted) return;
      
      // Close loading dialog if it's still open
      Navigator.of(context).pop();
      
      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error, color: Colors.red, size: 48),
          title: FutureBuilder<String>(
            future: widget.translate('Error'),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? 'Error',
                style: const TextStyle(color: Colors.red),
              );
            },
          ),
          content: FutureBuilder<String>(
            future: widget.translate('Failed to delete files: $e'),
            builder: (context, snapshot) {
              return Text(snapshot.data ?? 'Failed to delete files: $e');
            },
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: FutureBuilder<String>(
                future: widget.translate('OK'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'OK');
                },
              ),
            ),
          ],
        ),
      );
    }
  }
}