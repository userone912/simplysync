# simplySync - Technical Architecture Guide

## 🏗️ **Application Architecture Overview**

simplySync follows a modern Android architecture pattern with clear separation of concerns, reactive state management, and efficient background processing.

### **Architecture Layers**

```
┌─────────────────────────────────────┐
│            UI Layer (Screens)       │
│  home | settings | folders | history│
├─────────────────────────────────────┤
│         State Management (BLoC)     │
│  ServerConfig | Folders | Sync | App│
├─────────────────────────────────────┤
│            Service Layer            │
│  Sync | Background | Database | ... │
├─────────────────────────────────────┤
│             Data Layer              │
│   Models | SQLite | SharedPrefs    │
└─────────────────────────────────────┘
```

## 📁 **Directory Structure**

```
lib/
├── bloc/                 # State management (BLoC pattern)
│   ├── app_bloc_provider.dart
│   ├── app_settings_bloc.dart
│   ├── server_config_bloc.dart
│   ├── synced_folders_bloc.dart
│   └── sync_operation_bloc.dart
├── models/               # Data models
│   ├── remote_item.dart
│   ├── scheduler_config.dart
│   ├── server_config.dart
│   ├── synced_folder.dart
│   └── sync_record.dart
├── screens/              # UI screens
│   ├── home_screen.dart
│   ├── onboarding_screen.dart
│   ├── remote_folder_browser_screen.dart
│   ├── simple_folders_screen.dart
│   ├── simple_history_screen.dart
│   └── simple_settings_screen.dart
├── services/             # Business logic services
│   ├── background_sync_monitor.dart
│   ├── background_sync_service.dart
│   ├── conflict_resolution.dart
│   ├── database_service.dart
│   ├── file_metadata_service.dart
│   ├── file_scanner_service.dart
│   ├── file_sync_service.dart
│   ├── notification_service.dart
│   ├── permission_service.dart
│   └── settings_service.dart
├── utils/                # Utilities
│   └── logger.dart
└── main.dart            # Application entry point
```

## 🔄 **State Management (BLoC Architecture)**

### **BLoC Separation Strategy**

The app uses four focused BLoCs instead of a monolithic approach:

#### **1. ServerConfigBloc**
- **Responsibility**: Server configuration and connection testing
- **Events**: 
  - `LoadServerConfig` - Load saved server configuration
  - `SaveServerConfig` - Save server configuration
  - `TestConnection` - Test server connectivity
- **States**:
  - `ServerConfigInitial` - Initial state
  - `ServerConfigLoading` - Loading/testing in progress
  - `ServerConfigLoaded` - Configuration loaded
  - `ServerConfigError` - Error state

#### **2. SyncedFoldersBloc**
- **Responsibility**: Folder selection and management
- **Events**:
  - `LoadSyncedFolders` - Load configured folders
  - `AddSyncedFolder` - Add new folder to sync
  - `RemoveSyncedFolder` - Remove folder from sync
  - `UpdateSyncedFolder` - Update folder configuration
- **States**:
  - `SyncedFoldersInitial` - Initial state
  - `SyncedFoldersLoading` - Loading folders
  - `SyncedFoldersLoaded` - Folders loaded
  - `SyncedFoldersError` - Error state

#### **3. SyncOperationBloc**
- **Responsibility**: Sync operations and progress tracking
- **Events**:
  - `StartSync` - Begin manual sync
  - `CancelSync` - Cancel ongoing sync
  - `LoadSyncHistory` - Load sync history records
- **States**:
  - `SyncOperationInitial` - Initial state
  - `SyncOperationInProgress` - Sync in progress
  - `SyncOperationCompleted` - Sync completed
  - `SyncOperationError` - Sync failed

#### **4. AppSettingsBloc**
- **Responsibility**: App settings and permissions
- **Events**:
  - `LoadAppSettings` - Load app configuration
  - `SaveSchedulerConfig` - Save sync schedule
  - `SetAutoDelete` - Configure auto-delete
  - `RequestPermissions` - Request Android permissions
- **States**:
  - `AppSettingsInitial` - Initial state
  - `AppSettingsLoading` - Loading settings
  - `AppSettingsLoaded` - Settings loaded
  - `AppSettingsError` - Error state

### **BLoC Provider Setup**

```dart
class AppBlocProvider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ServerConfigBloc()),
        BlocProvider(create: (_) => SyncedFoldersBloc()),
        BlocProvider(create: (_) => SyncOperationBloc()),
        BlocProvider(create: (_) => AppSettingsBloc()),
      ],
      child: MaterialApp(...),
    );
  }
}
```

## 🔧 **Service Layer Architecture**

### **Core Services**

#### **FileSyncService**
- **Purpose**: Multi-protocol file synchronization engine
- **Protocols Supported**: FTP/FTPS, SSH/SFTP, WebDAV/HTTPS
- **Key Methods**:
  - `syncFile()` - Sync individual file
  - `syncFilesBatch()` - Batch file processing
  - `listRemoteDirectory()` - Browse remote folders
  - `testConnection()` - Verify server connectivity

#### **BackgroundSyncService**
- **Purpose**: Scheduled background synchronization
- **Integration**: Android WorkManager
- **Features**:
  - Battery-optimized scheduling
  - Network constraint awareness
  - Progress monitoring
  - Cancellation support

#### **DatabaseService**  
- **Purpose**: SQLite data persistence
- **Tables**:
  - `sync_records` - Individual sync operations
  - `synced_folders` - Configured folders
  - Database versioning and migration

#### **NotificationService**
- **Purpose**: System notification management
- **Features**:
  - Silent notifications (no vibration/sound)
  - Progress updates during sync
  - Completion and error notifications
  - Android notification channels

## 📊 **Data Models**

### **Core Models**

#### **ServerConfig**
```dart
class ServerConfig {
  final SyncMode syncMode;           // ftp, ssh, webdav
  final String hostname;
  final int port;
  final String username;
  final String password;
  final bool useSSL;                 // FTPS/HTTPS support
  final AuthType authType;           // password, token, key
  final String? bearerToken;         // WebDAV token auth
  final String? baseUrl;             // WebDAV full URL
}
```

#### **SchedulerConfig**
```dart
class SchedulerConfig {
  final bool enabled;
  final SyncScheduleType scheduleType;  // interval, daily, weekly
  final int intervalMinutes;            // For interval mode
  final int syncHour;                   // For daily/weekly
  final int syncMinute;                 // For daily/weekly
  final int weekDay;                    // For weekly (1-7)
  final bool syncOnlyOnWifi;
  final bool syncOnlyWhenCharging;
}
```

#### **SyncRecord**
```dart
class SyncRecord {
  final String id;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String hash;
  final DateTime lastModified;
  final SyncStatus status;              // completed, failed, syncing
  final DateTime? syncedAt;
  final String? errorMessage;
}
```

## 🔐 **Security Architecture**

### **Data Protection**
- **Local Storage**: All credentials stored locally using SharedPreferences
- **No Cloud Dependencies**: Direct device-to-server communication
- **Encrypted Protocols**: SFTP, FTPS, HTTPS support
- **Input Validation**: All user inputs sanitized and validated

### **Authentication Flows**

#### **FTP/FTPS**
```
User → Username/Password → FTP Server
                        ↓
Optional SSL/TLS encryption
```

#### **SSH/SFTP**  
```
User → Username/Password → SSH Server → SFTP Channel
                        ↓
Built-in SSH encryption
```

#### **WebDAV**
```
User → Username/Password OR Bearer Token → WebDAV Server
                                        ↓
Optional HTTPS encryption
```

## 🚀 **Performance Optimizations**

### **Memory Management**
- **Lazy Loading**: BLoCs load data only when needed
- **Stream Cleanup**: Proper disposal of all streams and subscriptions  
- **Connection Pooling**: Reuse connections within sync sessions
- **Resource Cleanup**: Automatic cleanup of expired sessions

### **Network Efficiency**
- **Batch Processing**: Process multiple files in configurable batches
- **Retry Logic**: Exponential backoff for failed operations
- **Connection Reuse**: Minimize connection overhead
- **Protocol Optimization**: Use most efficient methods for each protocol

### **Battery Optimization**
- **Minimum Intervals**: Enforce 15-minute minimum for interval sync
- **Constraint Awareness**: Respect WiFi-only and charging-only settings
- **Background Optimization**: Use Android WorkManager best practices
- **Resource Monitoring**: Track and limit resource usage

## 📱 **Platform Integration**

### **Android Features**
- **WorkManager**: Background task scheduling
- **Scoped Storage**: Compliant file access
- **Material 3**: Modern Android design
- **Permissions**: Runtime permission management
- **Notifications**: System notification integration

### **File System Integration**
- **Media Folders**: Access to common media directories
- **Custom Folders**: User-selected folder access
- **File Metadata**: Size, modification date, type detection
- **Path Resolution**: Handle different Android storage paths

## 🔄 **Data Flow**

### **Sync Operation Flow**
```
User Trigger → SyncOperationBloc → BackgroundSyncService
     ↓                                       ↓
UI Updates ←← Progress Events ←← FileSyncService
     ↓                                       ↓
History Screen ←← DatabaseService ←← Sync Results
```

### **Configuration Flow**
```
Settings UI → ServerConfigBloc → SettingsService
     ↓                                    ↓
UI Updates ←← Validation Results ←← Database Storage
```

## 🧪 **Testing Strategy**

### **Unit Testing**
- BLoC state transitions
- Service method functionality
- Model serialization/deserialization
- Utility functions

### **Integration Testing**
- BLoC-Service interactions
- Database operations
- Network protocol handling
- Permission workflows

### **Widget Testing**
- Screen rendering
- User interaction flows
- State-dependent UI updates
- Navigation between screens

This architecture ensures maintainability, testability, and scalability while providing a smooth user experience and reliable background synchronization.