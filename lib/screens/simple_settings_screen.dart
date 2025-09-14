import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_settings_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import 'remote_folder_browser_screen.dart';

class SimpleSettingsScreen extends StatefulWidget {
  const SimpleSettingsScreen({super.key});

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
          title: const Text('Settings'),
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
                          Text(
                            'Server Configuration',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Protocol Selection
                          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          SegmentedButton<SyncMode>(
                            segments: const [
                              ButtonSegment(value: SyncMode.ftp, label: Text('FTP')),
                              ButtonSegment(value: SyncMode.ssh, label: Text('SSH')),
                              ButtonSegment(value: SyncMode.webdav, label: Text('WebDAV')),
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
                            TextField(
                              controller: _baseUrlController,
                              decoration: const InputDecoration(
                                labelText: 'WebDAV URL',
                                hintText: 'https://cloud.example.com/remote.php/dav/files/username/',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ] else ...[
                            TextField(
                              controller: _hostnameController,
                              decoration: const InputDecoration(
                                labelText: 'Server Address',
                                hintText: 'e.g., 192.168.1.100 or myserver.com',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          
                          TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
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
                                  child: Text(
                                    _selectedProtocol == SyncMode.ftp 
                                        ? 'Use FTPS (SSL/TLS)' 
                                        : 'Use HTTPS',
                                    style: Theme.of(context).textTheme.bodyMedium,
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
                                labelText: 'Authentication',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: AuthType.password,
                                  child: Text('Username/Password'),
                                ),
                                DropdownMenuItem(
                                  value: AuthType.token,
                                  child: Text('Bearer Token'),
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
                              TextField(
                                controller: _bearerTokenController,
                                decoration: const InputDecoration(
                                  labelText: 'Bearer Token',
                                  hintText: 'Enter your access token',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                          
                          // Remote Path Selection - moved to end of server config
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _remotePathController,
                                  decoration: const InputDecoration(
                                    labelText: 'Remote Path',
                                    hintText: '/',
                                    border: OutlineInputBorder(),
                                  ),
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
                          Text(
                            'Auto Sync',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          SwitchListTile(
                            title: const Text('Enable Auto Sync'),
                            subtitle: const Text('Automatically sync files in background'),
                            value: _autoSyncEnabled,
                            onChanged: (value) {
                              setState(() => _autoSyncEnabled = value);
                            },
                          ),
                          
                          if (_autoSyncEnabled) ...[
                            const SizedBox(height: 16),
                            
                            // Schedule Type Selection
                            Text('Schedule Type', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            SegmentedButton<SyncScheduleType>(
                              segments: const [
                                ButtonSegment(
                                  value: SyncScheduleType.interval, 
                                  label: Text('Interval'),
                                  tooltip: 'Sync every few minutes/hours',
                                ),
                                ButtonSegment(
                                  value: SyncScheduleType.daily, 
                                  label: Text('Daily'),
                                  tooltip: 'Sync once per day at specific time',
                                ),
                                ButtonSegment(
                                  value: SyncScheduleType.weekly, 
                                  label: Text('Weekly'),
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
                              Text('Sync Interval', style: Theme.of(context).textTheme.titleMedium),
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
                              Text(
                                'Sync every ${_syncIntervalMinutes < 60 ? '$_syncIntervalMinutes minutes' : '${(_syncIntervalMinutes / 60).toStringAsFixed(1)} hours'}',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ] else if (_scheduleType == SyncScheduleType.daily) ...[
                              Text('Daily Sync Time', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Card(
                                child: ListTile(
                                  leading: const Icon(Icons.schedule),
                                  title: const Text('Sync Time'),
                                  subtitle: Text('${_syncHour.toString().padLeft(2, '0')}:${_syncMinute.toString().padLeft(2, '0')}'),
                                  trailing: const Icon(Icons.edit),
                                  onTap: () => _showTimePicker(context),
                                ),
                              ),
                            ] else if (_scheduleType == SyncScheduleType.weekly) ...[
                              Text('Weekly Sync Schedule', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.calendar_today),
                                      title: const Text('Day of Week'),
                                      subtitle: Text(_getWeekdayName(_weekDay)),
                                      trailing: const Icon(Icons.edit),
                                      onTap: () => _showWeekdayPicker(context),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.schedule),
                                      title: const Text('Sync Time'),
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
                              title: const Text('WiFi Only'),
                              subtitle: const Text('Only sync when connected to WiFi'),
                              value: _wifiOnlySync,
                              onChanged: (value) {
                                setState(() => _wifiOnlySync = value);
                              },
                            ),
                            
                            SwitchListTile(
                              title: const Text('Charging Only'),
                              subtitle: const Text('Only sync when device is charging'),
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
                              Text(
                                'Auto Delete Files',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
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
                                const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.dangerous, color: Colors.red, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'WARNING: This will PERMANENTLY DELETE local files after sync!',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '• Files will be deleted from your device immediately after successful sync\n'
                                  '• This action cannot be undone\n'
                                  '• Only enable if you want to move (not copy) files to the server\n'
                                  '• Make sure your sync is working perfectly before enabling this',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          SwitchListTile(
                            title: const Text(
                              'Delete Local Files After Sync',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: const Text(
                              'Files will be permanently deleted from device after successful upload',
                              style: TextStyle(fontSize: 12),
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
                child: const Text('Save Settings', style: TextStyle(fontSize: 16)),
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
}