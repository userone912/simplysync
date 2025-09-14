import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/server_config_bloc.dart';
import '../bloc/synced_folders_bloc.dart';
import '../bloc/sync_operation_bloc.dart';
import '../bloc/app_settings_bloc.dart';
import '../bloc/app_bloc_provider.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';
import '../models/sync_record.dart';
import '../services/translation_service.dart';
import '../widgets/banner_ad_widget.dart';
import 'simple_folders_screen.dart';
import 'simple_history_screen.dart';
import 'simple_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Future<String> Function(String) translate;
  final void Function(Locale) changeLocale;
  final Locale currentLocale;

  const HomeScreen({
    super.key,
    required this.translate,
    required this.changeLocale,
    required this.currentLocale,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  late AnimationController _syncAnimationController;
  ServerConfig? _lastServerConfig;
  
  // Navigation labels - will be updated when language changes
  String _homeLabel = 'Dashboard';
  String _foldersLabel = 'Folders';
  String _historyLabel = 'History';
  String _settingsLabel = 'Settings';
  
  // For cleaner UI, use a single summary card and more whitespace

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    // Load navigation labels
    _updateNavigationLabels();
    
    // Lazy load data only when dashboard tab is active
    if (_selectedIndex == 0) {
      _loadDashboardData();
    }
  }

  void _updateNavigationLabels() async {
    final home = await widget.translate('Dashboard');
    final folders = await widget.translate('Folders');  
    final history = await widget.translate('History');
    final settings = await widget.translate('Settings');
    
    if (mounted) {
      setState(() {
        _homeLabel = home;
        _foldersLabel = folders;
        _historyLabel = history;
        _settingsLabel = settings;
      });
    }
  }

  void _loadDashboardData() {
    // Only load data when actually needed
    context.serverConfigBloc.add(LoadServerConfig());
    context.syncedFoldersBloc.add(LoadSyncedFolders());
    context.syncOperationBloc.add(LoadSyncHistory());
    context.appSettingsBloc.add(LoadAppSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          context.serverConfigBloc.add(LoadServerConfig());
          context.syncedFoldersBloc.add(LoadSyncedFolders());
          context.syncOperationBloc.add(LoadSyncHistory());
          context.appSettingsBloc.add(LoadAppSettings());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside text fields
        FocusScope.of(context).unfocus();
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
        appBar: _selectedIndex == 0 ? AppBar(
          backgroundColor: Theme.of(context).colorScheme.background,
          elevation: 0,
          actions: [
            PopupMenuButton<dynamic>(
              onSelected: (value) {
                if (value == 'device') {
                  // Reset to device language
                  TranslationService.resetToDeviceLanguage().then((_) {
                    setState(() {
                      // Update will be handled by the callback from main.dart
                    });
                    widget.changeLocale(TranslationService.currentLocale);
                    _updateNavigationLabels(); // Update navigation labels
                  });
                } else if (value is Locale) {
                  widget.changeLocale(value);
                  _updateNavigationLabels(); // Update navigation labels
                }
              },
              onCanceled: () {
                // Popup cancelled, nothing special needed
              },
              itemBuilder: (context) {
                final items = <PopupMenuItem<dynamic>>[];
                
                // Check if we're actually using device language (not user override)
                final isUsingDeviceLanguage = !TranslationService.isUserOverride;
                
                // Add "Use Device Language" option
                items.add(PopupMenuItem<String>(
                  value: 'device',
                  child: Row(
                    children: [
                      Icon(
                        isUsingDeviceLanguage
                            ? Icons.check
                            : Icons.smartphone,
                        size: 16,
                        color: isUsingDeviceLanguage
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Use Device Language',
                        style: TextStyle(
                          fontWeight: isUsingDeviceLanguage
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ));
                
                // Add divider
                items.add(const PopupMenuItem<String>(
                  enabled: false,
                  child: Divider(height: 1),
                ));
                
                // Add language options
                items.addAll(
                  TranslationService.supportedLanguages.map((lang) {
                    final locale = lang['locale'] as Locale;
                    final isSelected = TranslationService.isUserOverride && 
                                     widget.currentLocale.languageCode == locale.languageCode;
                    
                    return PopupMenuItem<Locale>(
                      value: locale,
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check : Icons.language,
                            size: 16,
                            color: isSelected 
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            lang['name'],
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
                
                return items;
              },
              icon: const Icon(Icons.language),
              tooltip: widget.currentLocale.languageCode == 'en' ? 'Change Language' : 'Change Language',
            ),
          ],
        ) : null,
        body: MultiBlocListener(
          listeners: [
            BlocListener<SyncOperationBloc, SyncOperationState>(
              listener: (context, state) {
                if (state is SyncInProgress) {
                  _syncAnimationController.repeat();
                } else {
                  _syncAnimationController.stop();
                  _syncAnimationController.reset();
                }
                if (state is SyncError) {
                  String errorMsg = state.message;
                  if (errorMsg.toLowerCase().contains('cancelled')) {
                    widget.translate('Sync cancelled by user').then((translated) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(translated),
                          backgroundColor: Colors.red,
                        ),
                      );
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMsg),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else if (state is SyncSuccess) {
                  widget.translate('Sync completed: ${state.syncedCount} files, ${state.errorCount} errors').then((translated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(translated),
                        backgroundColor: Colors.green,
                      ),
                    );
                  });
                }
              },
            ),
            BlocListener<ServerConfigBloc, ServerConfigState>(
              listener: (context, state) {
                if (state is ConnectionTestSuccess) {
                  widget.translate('Connection test successful!').then((translated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(translated),
                        backgroundColor: Colors.green,
                      ),
                    );
                  });
                } else if (state is ConnectionTestFailure) {
                  widget.translate('Connection failed: ${state.message}').then((translated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(translated),
                        backgroundColor: Colors.red,
                      ),
                    );
                  });
                }
              },
            ),
          ],
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              // Dashboard - simplified for background sync focus
              RefreshIndicator(
                onRefresh: () async {
                  _loadDashboardData();
                  // Add a small delay for better UX
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              Theme.of(context).colorScheme.secondary.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Compact header with app info and status in one row
                            Row(
                              children: [
                                // App icon (smaller and cleaner)
                                Container(
                                  width: 60,
                                  height: 60,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/images/icon.png',
                                    width: 44,
                                    height: 44,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // App info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Simply Sync',
                                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FutureBuilder<String>(
                                        future: widget.translate('File Synchronization'),
                                        builder: (context, snapshot) => Text(
                                          snapshot.data ?? 'File Synchronization',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Status indicator (compact)
                                _buildCompactStatus(
                                  context.watch<SyncOperationBloc>().state,
                                  context.watch<AppSettingsBloc>().state,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Compact progress indicator when syncing
                      BlocBuilder<SyncOperationBloc, SyncOperationState>(
                        builder: (context, syncState) {
                          if (syncState is SyncInProgress) {
                            return Column(
                              children: [
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              syncState.currentFileName ?? 'Processing...',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${syncState.currentFile}/${syncState.totalFiles}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: syncState.overallProgress,
                                          backgroundColor: Colors.grey[200],
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(syncState.overallProgress * 100).toInt()}% complete',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(height: 20),
                      // Quick stats overview
                      _buildQuickStats(
                        context.watch<SyncOperationBloc>().state,
                        context.watch<AppSettingsBloc>().state,
                      ),
                      const SizedBox(height: 20),
                      // Automation status card
                      _buildAutomationCard(context.watch<AppSettingsBloc>().state),
                      const SizedBox(height: 20),
                      // Quick actions card
                      _buildQuickActions(context.watch<AppSettingsBloc>().state),
                      const SizedBox(height: 100), // Extra space for FAB
                    ],
                  ),
                ),
              ),
              // Folders
              SimpleFoldersScreen(translate: widget.translate),
              // History
              SimpleHistoryScreen(translate: widget.translate),
              // Settings
              SimpleSettingsScreen(translate: widget.translate),
            ],
          ),
        ),
        floatingActionButton: _selectedIndex == 0 ? _buildFloatingActionButton() : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner ad above navigation
            const BannerAdWidget(
              margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
                
                // Lazy load data only when switching to dashboard
                if (index == 0) {
                  _loadDashboardData();
                }
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.dashboard),
                  label: _homeLabel,
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder),
                  label: _foldersLabel,
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: _historyLabel,
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: _settingsLabel,
                ),
              ],
            ),
          ],
        ),
        ), // Close SafeArea
      ), // Close GestureDetector
    );
  }

  Widget _buildCompactStatus(SyncOperationState syncState, AppSettingsState settingsState) {
    String statusText = 'Ready';
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle;

    // Check server config and folder setup
    final serverConfigState = context.watch<ServerConfigBloc>().state;
    if (serverConfigState is ServerConfigLoaded && serverConfigState.config != null) {
      _lastServerConfig = serverConfigState.config;
    } else if (serverConfigState is ServerConfigInitial) {
      _lastServerConfig = null;
    }
    
    final hasServerConfig = _lastServerConfig != null;
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);

    if (!hasServerConfig) {
      statusText = 'Setup Required';
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_off;
    } else if (!hasEnabledFolder) {
      statusText = 'Select Folders';
      statusColor = Colors.orange;
      statusIcon = Icons.folder_off;
    } else if (syncState is SyncInProgress) {
      statusText = 'Syncing';
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else if (syncState is SyncError) {
      statusText = 'Error';
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return FutureBuilder<String>(
      future: widget.translate(statusText),
      builder: (context, snapshot) {
        final translatedText = snapshot.data ?? statusText;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: syncState is SyncInProgress
                    ? RotationTransition(
                        key: const ValueKey('sync_icon'),
                        turns: _syncAnimationController,
                        child: Icon(statusIcon, size: 16, color: statusColor),
                      )
                    : Icon(
                        key: ValueKey(statusIcon),
                        statusIcon,
                        size: 16,
                        color: statusColor,
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                translatedText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /*
  // REMOVED: Old _buildMainStatus method - replaced with compact status badge
  Widget _buildMainStatus(SyncOperationState syncState, AppSettingsState settingsState) {
    String statusText = 'Ready';
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle;

    // Check server config and folder setup
    final serverConfigState = context.watch<ServerConfigBloc>().state;
    if (serverConfigState is ServerConfigLoaded && serverConfigState.config != null) {
      _lastServerConfig = serverConfigState.config;
    } else if (serverConfigState is ServerConfigInitial) {
      _lastServerConfig = null;
    }
    
    final hasServerConfig = _lastServerConfig != null;
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);

    if (!hasServerConfig) {
      statusText = 'No Server Configured';
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_off;
    } else if (!hasEnabledFolder) {
      statusText = 'No Folders Selected';
      statusColor = Colors.orange;
      statusIcon = Icons.folder_off;
    } else if (syncState is SyncInProgress) {
      statusText = 'Syncing...';
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else if (syncState is SyncError) {
      statusText = 'Sync Error';
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Column(
      children: [
        // Status Icon with animated container
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: syncState is SyncInProgress
                ? RotationTransition(
                    key: const ValueKey('sync_icon'),
                    turns: _syncAnimationController,
                    child: Icon(statusIcon, size: 36, color: statusColor),
                  )
                : Icon(
                    key: ValueKey(statusIcon),
                    statusIcon,
                    size: 36,
                    color: statusColor,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Status Text
        Text(
          statusText,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        // Progress indicator for sync
        if (syncState is SyncInProgress) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      syncState.currentFileName ?? 'Processing...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${syncState.currentFile}/${syncState.totalFiles}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: syncState.overallProgress,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(syncState.overallProgress * 100).toInt()}% complete',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ] else if (hasServerConfig && hasEnabledFolder) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 16, color: Colors.green[700]),
                const SizedBox(width: 4),
                Text(
                  'All set up',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
  */

  Widget _buildQuickStats(SyncOperationState syncState, AppSettingsState settingsState) {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<String>(
            future: widget.translate('Last Sync'),
            builder: (context, snapshot) {
              return _buildStatCard(
                icon: Icons.history_rounded,
                title: snapshot.data ?? 'Last Sync',
                value: _getLastSyncTime(syncState),
                color: Colors.blue,
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FutureBuilder<String>(
            future: widget.translate('Success Rate'),
            builder: (context, snapshot) {
              return _buildStatCard(
                icon: Icons.check_circle_rounded,
                title: snapshot.data ?? 'Success Rate',
                value: _getSyncSuccessRate(syncState),
                color: Colors.green,
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FutureBuilder<String>(
            future: widget.translate('Active Folders'),
            builder: (context, snapshot) {
              return _buildStatCard(
                icon: Icons.folder_rounded,
                title: snapshot.data ?? 'Active Folders',
                value: _getActiveFoldersCount(),
                color: Colors.orange,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _getLastSyncTime(SyncOperationState syncState) {
    if (syncState is SyncOperationLoaded && syncState.syncHistory.isNotEmpty) {
      final lastRecord = syncState.syncHistory.first;
      if (lastRecord.syncedAt != null) {
        final duration = DateTime.now().difference(lastRecord.syncedAt!);
        if (duration.inMinutes < 1) return 'Now';
        if (duration.inHours < 1) return '${duration.inMinutes}m ago';
        if (duration.inDays < 1) return '${duration.inHours}h ago';
        return '${duration.inDays}d ago';
      }
    }
    return 'Never';
  }

  String _getSyncSuccessRate(SyncOperationState syncState) {
    if (syncState is SyncOperationLoaded && syncState.syncHistory.isNotEmpty) {
      final total = syncState.syncHistory.length;
      final successful = syncState.syncHistory.where((r) => r.status == SyncStatus.completed).length;
      final rate = (successful / total * 100).round();
      return '$rate%';
    }
    return '0%';
  }

  String _getActiveFoldersCount() {
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    if (foldersState is SyncedFoldersLoaded) {
      final activeCount = foldersState.folders.where((f) => f.enabled).length;
      return '$activeCount';
    }
    return '0';
  }

  Widget _buildAutomationCard(AppSettingsState settingsState) {
    if (settingsState is! AppSettingsLoaded) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(width: 16),
              FutureBuilder<String>(
                future: widget.translate('Loading automation settings...'),
                builder: (context, snapshot) {
                  return Text(snapshot.data ?? 'Loading automation settings...');
                },
              ),
            ],
          ),
        ),
      );
    }
    
    final config = settingsState.schedulerConfig;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: config.enabled ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.schedule,
                    color: config.enabled ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                FutureBuilder<String>(
                  future: widget.translate('Automation'),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? 'Automation',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Auto Sync Status
            FutureBuilder<String>(
              future: widget.translate('Auto Sync'),
              builder: (context, snapshot) {
                return FutureBuilder<String>(
                  future: widget.translate(config.enabled ? _getScheduleDescription(config) : 'Disabled'),
                  builder: (context, subtitleSnapshot) {
                    return _buildFeatureStatus(
                      icon: Icons.sync,
                      title: snapshot.data ?? 'Auto Sync',
                      enabled: config.enabled,
                      enabledColor: Colors.green,
                      subtitle: subtitleSnapshot.data ?? (config.enabled 
                        ? _getScheduleDescription(config)
                        : 'Disabled'),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            // Auto Delete Status
            FutureBuilder<String>(
              future: widget.translate('Auto Delete'),
              builder: (context, snapshot) {
                return FutureBuilder<String>(
                  future: widget.translate(settingsState.autoDeleteEnabled 
                    ? 'Files deleted after sync'
                    : 'Files kept after sync'),
                  builder: (context, subtitleSnapshot) {
                    return _buildFeatureStatus(
                      icon: settingsState.autoDeleteEnabled ? Icons.auto_delete : Icons.auto_delete_outlined,
                      title: snapshot.data ?? 'Auto Delete',
                      enabled: settingsState.autoDeleteEnabled,
                      enabledColor: Colors.orange,
                      subtitle: subtitleSnapshot.data ?? (settingsState.autoDeleteEnabled 
                        ? 'Files deleted after sync'
                        : 'Files kept after sync'),
                    );
                  },
                );
              },
            ),
            // Constraints chips
            if (config.enabled && (config.syncOnlyOnWifi || config.syncOnlyWhenCharging)) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (config.syncOnlyOnWifi)
                    FutureBuilder<String>(
                      future: widget.translate('WiFi Only'),
                      builder: (context, snapshot) {
                        return Chip(
                          avatar: Icon(Icons.wifi, size: 16, color: Colors.blue),
                          label: Text(snapshot.data ?? 'WiFi Only'),
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          labelStyle: TextStyle(color: Colors.blue[700]),
                        );
                      },
                    ),
                  if (config.syncOnlyWhenCharging)
                    FutureBuilder<String>(
                      future: widget.translate('Charging Only'),
                      builder: (context, snapshot) {
                        return Chip(
                          avatar: Icon(Icons.battery_charging_full, size: 16, color: Colors.green),
                          label: Text(snapshot.data ?? 'Charging Only'),
                          backgroundColor: Colors.green.withOpacity(0.1),
                          labelStyle: TextStyle(color: Colors.green[700]),
                        );
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureStatus({
    required IconData icon,
    required String title,
    required bool enabled,
    required Color enabledColor,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled ? enabledColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            color: enabled ? enabledColor : Colors.grey,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled ? enabledColor : Colors.grey,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<String>(
          future: widget.translate(enabled ? 'Active' : 'Inactive'),
          builder: (context, snapshot) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: enabled ? enabledColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                snapshot.data ?? (enabled ? 'Active' : 'Inactive'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: enabled ? enabledColor : Colors.grey,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _getScheduleDescription(config) {
    switch (config.scheduleType) {
      case SyncScheduleType.daily:
        return 'Daily at ${config.dailySyncHour}:${config.dailySyncMinute.toString().padLeft(2, '0')}';
      case SyncScheduleType.weekly:
        final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return '${weekdays[config.weeklySyncDay]} at ${config.weeklySyncHour}:${config.weeklySyncMinute.toString().padLeft(2, '0')}';
      case SyncScheduleType.interval:
      default:
        return 'Every ${config.intervalMinutes} minutes';
    }
  }

  Widget _buildQuickActions(AppSettingsState settingsState) {
    // Use last known server config logic (persisted at State level)
    final serverConfigState = context.watch<ServerConfigBloc>().state;
    final isTestingConnection = serverConfigState is ConnectionTesting;
    final hasServerConfig = _lastServerConfig != null;
    final foldersState = context.watch<SyncedFoldersBloc>().state;
    final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.flash_on,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                FutureBuilder<String>(
                  future: widget.translate('Quick Actions'),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data ?? 'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: BlocBuilder<SyncOperationBloc, SyncOperationState>(
                    builder: (context, syncState) {
                      final isSyncInProgress = syncState is SyncInProgress || syncState is SyncCancelling;
                      
                      if (isSyncInProgress) {
                        // Show Cancel Sync button when sync is active
                        return FutureBuilder<String>(
                          future: widget.translate(syncState is SyncCancelling ? 'Cancelling...' : 'Cancel Sync'),
                          builder: (context, snapshot) {
                            return _buildActionButton(
                              icon: syncState is SyncCancelling ? Icons.hourglass_empty : Icons.stop,
                              label: snapshot.data ?? (syncState is SyncCancelling ? 'Cancelling...' : 'Cancel Sync'),
                              color: syncState is SyncCancelling ? Colors.orange : Colors.red,
                              onPressed: syncState is SyncCancelling ? null : () => context.syncOperationBloc.add(PauseSync()),
                            );
                          },
                        );
                      } else {
                        // Show normal Sync Now button
                        return BlocBuilder<AppSettingsBloc, AppSettingsState>(
                          builder: (context, state) {
                            final permissionsGranted = state is AppSettingsLoaded ? state.permissionsGranted : false;
                            final canSync = permissionsGranted && hasServerConfig && hasEnabledFolder;
                            return FutureBuilder<String>(
                              future: widget.translate('Sync Now'),
                              builder: (context, snapshot) {
                                return _buildActionButton(
                                  icon: canSync ? Icons.sync : Icons.sync_disabled,
                                  label: snapshot.data ?? 'Sync Now',
                                  color: canSync ? Colors.blue : Colors.grey,
                                  onPressed: canSync ? () => context.syncOperationBloc.add(StartSyncNow()) : null,
                                );
                              },
                            );
                          },
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FutureBuilder<String>(
                    future: widget.translate(isTestingConnection ? 'Testing...' : 'Test'),
                    builder: (context, snapshot) {
                      return _buildActionButton(
                        icon: isTestingConnection ? null : Icons.wifi,
                        label: snapshot.data ?? (isTestingConnection ? 'Testing...' : 'Test'),
                        color: hasServerConfig && !isTestingConnection ? Colors.green : Colors.grey,
                        onPressed: hasServerConfig && !isTestingConnection
                            ? () => context.serverConfigBloc.add(TestConnection())
                            : null,
                        isLoading: isTestingConnection,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? color : Colors.grey[300],
          foregroundColor: isEnabled ? Colors.white : Colors.grey[600],
          elevation: isEnabled ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            if ((isLoading || icon != null) && label.isNotEmpty)
              const SizedBox(width: 8),
            if (label.isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return BlocBuilder<SyncOperationBloc, SyncOperationState>(
      builder: (context, syncState) {
        final isSyncInProgress = syncState is SyncInProgress || syncState is SyncCancelling;
        
        return BlocBuilder<AppSettingsBloc, AppSettingsState>(
          builder: (context, settingsState) {
            final hasServerConfig = _lastServerConfig != null;
            final foldersState = context.watch<SyncedFoldersBloc>().state;
            final hasEnabledFolder = foldersState is SyncedFoldersLoaded && foldersState.folders.any((f) => f.enabled);
            final permissionsGranted = settingsState is AppSettingsLoaded ? settingsState.permissionsGranted : false;
            final canSync = permissionsGranted && hasServerConfig && hasEnabledFolder;

            if (isSyncInProgress) {
              // Show cancel button during sync
              return FutureBuilder<String>(
                future: widget.translate(syncState is SyncCancelling ? 'Stopping...' : 'Stop Sync'),
                builder: (context, snapshot) {
                  return FloatingActionButton.extended(
                    onPressed: syncState is SyncCancelling ? null : () => context.syncOperationBloc.add(PauseSync()),
                    backgroundColor: syncState is SyncCancelling ? Colors.orange : Colors.red,
                    foregroundColor: Colors.white,
                    icon: Icon(syncState is SyncCancelling ? Icons.hourglass_empty : Icons.stop),
                    label: Text(
                      snapshot.data ?? (syncState is SyncCancelling ? 'Stopping...' : 'Stop Sync'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    elevation: 4,
                  );
                },
              );
            } else {
              // Show sync button
              return FutureBuilder<String>(
                future: widget.translate('Quick Sync'),
                builder: (context, snapshot) {
                  return FloatingActionButton.extended(
                    onPressed: canSync ? () => context.syncOperationBloc.add(StartSyncNow()) : null,
                    backgroundColor: canSync ? Theme.of(context).colorScheme.primary : Colors.grey,
                    foregroundColor: Colors.white,
                    icon: Icon(canSync ? Icons.sync : Icons.sync_disabled),
                    label: Text(
                      snapshot.data ?? 'Quick Sync',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    elevation: canSync ? 6 : 2,
                  );
                },
              );
            }
          },
        );
      },
    );
  }
}
