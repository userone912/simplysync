# simplySync

A lightweight Android app for intelligent background file synchronization with remote servers.

## 🚀 Core Features

### 1. **Multi-Protocol Server Support**
- **FTP/FTPS** - Standard File Transfer Protocol with SSL/TLS support
- **SSH/SFTP** - Secure Shell File Transfer Protocol with key authentication  
- **WebDAV/HTTPS** - Web Distributed Authoring with bearer token support and robust path handling
- **Protocol-specific settings** - SSL toggles, authentication types, custom ports
- **Enhanced WebDAV** - Fixed path normalization, recursive directory creation, and header consistency

### 2. **Smart Folder Management**
- **Media Folder Sync** - Camera, Downloads, Pictures, Documents, Music
- **Custom folder picker** - Browse and select any device folder
- **Remote folder browser** - Navigate server directories interactively
- **Category-based organization** - Automatic file categorization on server

### 3. **Flexible Sync Scheduling**
- **Interval Sync** - Every 15 minutes to 6 hours (battery optimized)
- **Daily Sync** - Once per day at specific time (e.g., 9:00 AM)
- **Weekly Sync** - Once per week on chosen day/time (e.g., Sunday 6:00 PM)
- **Smart constraints** - WiFi-only, charging-only options
- **Background optimization** - Respects Android power management

### 4. **Advanced Sync Options**
- **Auto-delete files** - Optionally delete local files after successful sync
- **Conflict resolution** - Handle duplicate files (append, overwrite, skip)
- **Retry logic** - Automatic retry with exponential backoff
- **Progress tracking** - Real-time sync progress with file-by-file updates
- **Comprehensive logging** - Detailed sync history and error reporting

### 5. **Clean & Intuitive UI**
- **Material 3 Design** - Modern Android design language
- **Simplified onboarding** - Quick setup wizard
- **Real-time status** - Live sync progress and server connection status
- **Silent notifications** - Non-intrusive progress updates (no vibration/sound)
- **Smart focus management** - Automatic keyboard dismissal and gesture-based controls
- **Direct navigation** - "Set Up Sync" button takes users directly to settings
- **Multi-language support** - Seamless language switching without UI disruption

## 🏗️ Architecture

### **State Management**
- **BLoC Pattern** - Predictable state management with focused responsibilities
- **Separated Concerns** - Individual BLoCs for different app areas:
  - `ServerConfigBloc` - Server configuration and connection testing
  - `SyncedFoldersBloc` - Folder selection and management
  - `SyncOperationBloc` - Sync operations and progress tracking  
  - `AppSettingsBloc` - App settings and permissions

### **Background Processing**
- **WorkManager** - Reliable background sync with Android optimization
- **Isolate-based sync** - Heavy operations run in separate threads
- **Smart scheduling** - Respects system constraints and battery life
- **Persistent storage** - SQLite database for sync history and settings

### **Network Layer**
- **Protocol abstraction** - Unified interface for all sync protocols
- **Connection pooling** - Efficient reuse of server connections
- **Automatic retry** - Intelligent handling of network failures
- **File verification** - Checksum validation for data integrity

## 📱 Quick Setup

1. **Server Configuration**
   - Choose protocol (FTP/SSH/WebDAV)
   - Enter server details or WebDAV URL
   - Test connection with browse button

2. **Folder Selection** 
   - Pick common media folders or custom paths
   - Use remote browser to set server destination

3. **Sync Schedule**
   - Choose interval, daily, or weekly sync
   - Set time preferences and constraints
   - Configure auto-delete if desired

4. **Background Operation**
   - App automatically syncs based on schedule
   - Monitor progress through notifications
   - Review sync history anytime

## 🌐 Network Support

- **Local Network** - Home/office WiFi networks (192.168.x.x, 10.x.x.x)
- **Internet Servers** - Remote servers worldwide
- **VPN Support** - Works through VPN connections
- **IPv4/IPv6** - Full support for modern networking

## 🔒 Security & Privacy

- **Encrypted Protocols** - SFTP, FTPS, and HTTPS support
- **Local Storage** - All credentials stored securely on device
- **No Cloud Dependencies** - Direct device-to-server communication
- **Token Authentication** - Bearer token support for WebDAV services

## 📊 Performance Features

- **Battery Optimized** - Intelligent scheduling respects power management
- **Network Efficient** - Minimal data usage with smart retry logic
- **Memory Safe** - Proper resource cleanup and connection management
- **Fast Sync** - Concurrent file processing with configurable batch sizes

The app prioritizes battery life and minimal resource usage while maintaining reliable sync functionality.
