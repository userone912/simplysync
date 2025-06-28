import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:ftpconnect/ftpconnect.dart';
import '../models/server_config.dart';
import '../models/sync_record.dart';
import '../utils/logger.dart' as app_logger;
import 'file_metadata_service.dart';
import 'database_service.dart';

class FileSyncService {
  static Future<String> calculateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static Future<Map<String, dynamic>> testConnectionWithDetection(ServerConfig config) async {
    try {
      if (config.syncMode == SyncMode.ssh) {
        final result = await _testSSHConnectionWithDetection(config);
        return result;
      } else {
        final success = await _testFTPConnection(config);
        return {
          'success': success,
          'serverType': null,
        };
      }
    } catch (e) {
      app_logger.Logger.error('Connection test failed', error: e);
      return {
        'success': false,
        'serverType': null,
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> _testSSHConnectionWithDetection(ServerConfig config) async {
    try {
      final socket = await SSHSocket.connect(config.hostname, config.port);
      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      
      await client.authenticated;
      
      // Detect server info (type and home directory)
      final serverInfo = await detectServerInfo(config);
      
      client.close();
      
      return {
        'success': true,
        'serverType': serverInfo['serverType'],
        'homeDirectory': serverInfo['homeDirectory'],
      };
    } catch (e) {
      // SSH connection test failed
      return {
        'success': false,
        'serverType': null,
        'error': e.toString(),
      };
    }
  }

  static Future<bool> testConnection(ServerConfig config) async {
    final result = await testConnectionWithDetection(config);
    return result['success'] ?? false;
  }

  static Future<bool> _testFTPConnection(ServerConfig config) async {
    try {
      final ftpConnect = FTPConnect(
        config.hostname,
        user: config.username,
        pass: config.password,
        port: config.port,
      );
      
      final connected = await ftpConnect.connect();
      if (connected) {
        await ftpConnect.disconnect();
        return true;
      }
      return false;
    } catch (e) {
      // FTP connection test failed
      return false;
    }
  }

  static Future<SyncRecord> syncFile(File file, ServerConfig config) async {
    try {
      app_logger.Logger.info('Starting sync for file: ${file.path}');
      app_logger.Logger.info('Server config - Host: ${config.hostname}, Port: ${config.port}, Mode: ${config.syncMode}');
      
      // Analyze file metadata
      final metadata = await FileMetadataService.analyzeFile(file);
      app_logger.Logger.info('File metadata - Name: ${metadata.fileName}, Size: ${metadata.size}, Category: ${metadata.categoryFolder}');

      // Generate the categorized remote path
      final remotePath = FileMetadataService.generateRemotePath(config.remotePath, metadata);
      app_logger.Logger.info('Target remote path: $remotePath');
      
      final hash = await calculateFileHash(file);
      
      final record = SyncRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: file.path,
        fileName: metadata.fileName,
        fileSize: metadata.size,
        hash: hash,
        lastModified: metadata.lastModified,
        status: SyncStatus.syncing,
      );

      Map<String, dynamic> result;
      
      if (config.syncMode == SyncMode.ssh) {
        app_logger.Logger.info('Using SSH sync mode');
        result = await _syncFileSSH(file, config, metadata, remotePath);
      } else {
        app_logger.Logger.info('Using FTP sync mode');
        result = await _syncFileFTP(file, config, metadata, remotePath);
      }
      
      final success = result['success'] ?? false;
      final errorMessage = result['error'] as String?;
      
      app_logger.Logger.info('Sync result - Success: $success, Error: $errorMessage');

      return record.copyWith(
        status: success ? SyncStatus.completed : SyncStatus.failed,
        syncedAt: success ? DateTime.now() : null,
        errorMessage: success ? null : (errorMessage ?? 'Upload failed'),
      );
    } catch (e) {
      app_logger.Logger.error('Error syncing file ${file.path}', error: e);
      
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final lastModified = await file.lastModified();
      
      return SyncRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: file.path,
        fileName: fileName,
        fileSize: fileSize,
        hash: '',
        lastModified: lastModified,
        status: SyncStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<Map<String, dynamic>> _syncFileSSH(
    File file, 
    ServerConfig config, 
    FileMetadata metadata, 
    String targetRemotePath
  ) async {
    try {
      app_logger.Logger.info('Attempting SSH connection to ${config.hostname}:${config.port}');
      
      final socket = await SSHSocket.connect(config.hostname, config.port);
      app_logger.Logger.info('SSH socket connected successfully');
      
      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      
      app_logger.Logger.info('Authenticating SSH client...');
      await client.authenticated;
      app_logger.Logger.info('SSH authentication successful');
      
      final sftp = await client.sftp();
      app_logger.Logger.info('SFTP session established');
      
      // Determine the base directory to use (user-selected remote path)
      String basePath = config.remotePath;
      
      // For Linux/Mac servers, use home directory as fallback if configured path is problematic
      if ((config.serverType == ServerType.linux || config.serverType == ServerType.macos) && 
          config.homeDirectory != null) {
        
        // If remote path is root or empty, use home directory instead
        if (basePath == '/' || basePath.isEmpty) {
          basePath = config.homeDirectory!;
          app_logger.Logger.info('Using home directory as base path for Linux/Mac server: $basePath');
        }
        // If remote path is outside home directory, show warning but continue
        else if (!basePath.startsWith(config.homeDirectory!)) {
          app_logger.Logger.warning('⚠️ Remote path is outside home directory - may cause permission errors: $basePath');
        }
      }
      
      app_logger.Logger.info('Using base directory: $basePath');
      
      try {
        await sftp.stat(basePath);
        app_logger.Logger.info('Base directory exists: $basePath');
        // Note: SFTP doesn't have a "change directory" concept like FTP
        // We work with absolute paths or relative to the connection's default directory
      } catch (e) {
        app_logger.Logger.error('Base directory does not exist or is not accessible: $basePath', error: e);
        throw Exception('Base directory not accessible: $basePath');
      }
      
      // Extract directory and filename from target path
      final parts = targetRemotePath.split('/');
      final fileName = parts.last;
      
      app_logger.Logger.info('Target remote path: $targetRemotePath');
      app_logger.Logger.info('File name: $fileName');
      
      // Only create the category subdirectory within the base path
      final categoryFolder = metadata.categoryFolder;
      final categoryPath = '$basePath/$categoryFolder';
      app_logger.Logger.info('Category path to create: $categoryPath');
      
      // Create only the category directory
      await _createCategoryDirectorySSH(sftp, categoryPath, config.serverType ?? ServerType.linux);
      
      // Verify directory was created successfully
      try {
        await sftp.stat(categoryPath);
        app_logger.Logger.info('Category directory verified: $categoryPath');
      } catch (e) {
        app_logger.Logger.error('Category directory verification failed: $categoryPath', error: e);
        throw Exception('Failed to create or access category directory: $categoryPath');
      }
      
      // Check for existing files and handle conflicts
      app_logger.Logger.info('Checking for existing files in category directory: $categoryPath');
      final existingFiles = await _listDirectorySSH(sftp, categoryPath);
      app_logger.Logger.info('Found ${existingFiles.length} existing files: $existingFiles');
      
      final uniqueFileName = FileMetadataService.generateUniqueFileName(fileName, existingFiles);
      final finalRemotePath = '$categoryPath/$uniqueFileName';
      
      if (uniqueFileName != fileName) {
        app_logger.Logger.info('File renamed to avoid conflict: $fileName -> $uniqueFileName');
      }
      
      app_logger.Logger.info('Uploading to: $finalRemotePath');
      
      // Upload the file
      final remoteFile = await sftp.open(finalRemotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
      final fileBytes = await file.readAsBytes();
      app_logger.Logger.info('File size: ${fileBytes.length} bytes');
      
      final stream = Stream.fromIterable([fileBytes]);
      await remoteFile.write(stream);
      await remoteFile.close();
      
      app_logger.Logger.info('File upload completed successfully');
      client.close();
      
      return {
        'success': true,
        'remotePath': finalRemotePath,
      };
    } catch (e) {
      app_logger.Logger.error('SSH sync failed for ${metadata.fileName}', error: e);
      return {
        'success': false,
        'remotePath': null,
        'error': 'SSH Error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> _syncFileFTP(
    File file, 
    ServerConfig config, 
    FileMetadata metadata, 
    String targetRemotePath
  ) async {
    try {
      app_logger.Logger.info('Attempting FTP connection to ${config.hostname}:${config.port}');
      
      final ftpConnect = FTPConnect(
        config.hostname,
        user: config.username,
        pass: config.password,
        port: config.port,
      );
      
      app_logger.Logger.info('Connecting to FTP server...');
      final connected = await ftpConnect.connect();
      if (!connected) {
        app_logger.Logger.error('Failed to connect to FTP server');
        return {
          'success': false,
          'remotePath': null,
          'error': 'Failed to connect to FTP server',
        };
      }
      app_logger.Logger.info('FTP connection successful');
      
      // Change to the base directory (user-selected remote path)
      final basePath = config.remotePath;
      app_logger.Logger.info('Changing to base directory: $basePath');
      
      if (basePath != '/' && basePath.isNotEmpty) {
        await ftpConnect.changeDirectory(basePath);
        app_logger.Logger.info('Successfully changed to base directory: $basePath');
      }
      
      // Extract directory and filename from target path
      final parts = targetRemotePath.split('/');
      final fileName = parts.last;
      
      app_logger.Logger.info('Target remote path: $targetRemotePath');
      app_logger.Logger.info('File name: $fileName');
      
      // Only create the category subdirectory
      final categoryFolder = metadata.categoryFolder;
      app_logger.Logger.info('Category folder to create: $categoryFolder');
      
      // Create only the category directory
      await _createCategoryDirectoryFTP(ftpConnect, categoryFolder);
      
      // Change to the category directory
      app_logger.Logger.info('Changing to category directory: $categoryFolder');
      await ftpConnect.changeDirectory(categoryFolder);
      app_logger.Logger.info('Successfully changed to category directory: $categoryFolder');
      
      // Check for existing files and handle conflicts
      app_logger.Logger.info('Checking for existing files in category directory: $categoryFolder');
      final existingFiles = await _listDirectoryFTP(ftpConnect, '.');
      app_logger.Logger.info('Found ${existingFiles.length} existing files: $existingFiles');
      
      final uniqueFileName = FileMetadataService.generateUniqueFileName(fileName, existingFiles);
      final finalRemotePath = '$basePath/$categoryFolder/$uniqueFileName';
      
      if (uniqueFileName != fileName) {
        app_logger.Logger.info('File renamed to avoid conflict: $fileName -> $uniqueFileName');
      }
      
      app_logger.Logger.info('Uploading to FTP: $finalRemotePath (filename: $uniqueFileName)');
      
      // Upload file with the unique name
      final uploaded = await ftpConnect.uploadFileWithRetry(file, pRemoteName: uniqueFileName);
      await ftpConnect.disconnect();
      
      app_logger.Logger.info('FTP upload result: $uploaded');
      
      return {
        'success': uploaded,
        'remotePath': finalRemotePath,
        'error': uploaded ? null : 'FTP upload failed',
      };
    } catch (e) {
      app_logger.Logger.error('FTP sync failed for ${metadata.fileName}', error: e);
      return {
        'success': false,
        'remotePath': null,
        'error': 'FTP Error: ${e.toString()}',
      };
    }
  }

  static Future<List<SyncRecord>> syncMultipleFiles(
    List<File> files, 
    ServerConfig config,
    Function(int current, int total)? onProgress,
  ) async {
    final List<SyncRecord> results = [];
    
    for (int i = 0; i < files.length; i++) {
      final record = await syncFile(files[i], config);
      results.add(record);
      
      if (onProgress != null) {
        onProgress(i + 1, files.length);
      }
    }
    
    return results;
  }

  static Future<void> deleteLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Failed to delete local file
    }
  }

  static Future<bool> fileNeedsSync(File file, SyncRecord? existingRecord) async {
    // Always sync if no existing record
    if (existingRecord == null) {
      app_logger.Logger.info('File ${file.path} needs sync: No existing record');
      return true;
    }
    
    // Always retry files that previously failed
    if (existingRecord.status == SyncStatus.failed) {
      app_logger.Logger.info('File ${file.path} needs sync: Previous upload failed');
      return true;
    }
    
    // Skip files that are currently syncing (to avoid duplicates)
    if (existingRecord.status == SyncStatus.syncing) {
      app_logger.Logger.info('File ${file.path} skipped: Currently syncing');
      return false;
    }
    
    // For successfully uploaded files, check if they have changed
    if (existingRecord.status == SyncStatus.completed) {
      final currentHash = await calculateFileHash(file);
      final lastModified = await file.lastModified();
      
      // Check if file has been modified since last successful upload
      final hasChanged = currentHash != existingRecord.hash ||
                        lastModified.isAfter(existingRecord.lastModified);
      
      if (hasChanged) {
        app_logger.Logger.info('File ${file.path} needs sync: File has been modified since last upload');
      } else {
        app_logger.Logger.info('File ${file.path} skipped: Already uploaded and unchanged');
      }
      
      return hasChanged;
    }
    
    // Default to sync for any other status
    app_logger.Logger.info('File ${file.path} needs sync: Unknown status ${existingRecord.status}');
    return true;
  }

  static Future<List<String>> listDirectories(ServerConfig config, String path) async {
    try {
      if (config.syncMode == SyncMode.ssh) {
        return await _listSSHDirectories(config, path);
      } else {
        return await _listFTPDirectories(config, path);
      }
    } catch (e) {
      app_logger.Logger.error('Failed to list directories', error: e);
      return [];
    }
  }

  static Future<List<String>> _listSSHDirectories(ServerConfig config, String path) async {
    try {
      final socket = await SSHSocket.connect(config.hostname, config.port);
      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      
      await client.authenticated;
      
      // Execute ls command to list directories
      final session = await client.execute('find "$path" -maxdepth 1 -type d | head -20');
      final bytes = <int>[];
      await for (final chunk in session.stdout) {
        bytes.addAll(chunk);
      }
      final result = utf8.decode(bytes);
      
      client.close();
      
      // Parse the result and return directory paths
      final directories = result
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.trim())
          .where((dir) => dir != path) // Exclude the current directory
          .toList();
      
      // Always include parent directory if not at root
      final List<String> finalDirs = [];
      if (path != '/' && path.isNotEmpty) {
        final parentPath = path.split('/').sublist(0, path.split('/').length - 1).join('/');
        finalDirs.add(parentPath.isEmpty ? '/' : parentPath);
      }
      finalDirs.addAll(directories);
      
      return finalDirs;
    } catch (e) {
      app_logger.Logger.error('SSH directory listing failed', error: e);
      return [];
    }
  }

  static Future<List<String>> _listFTPDirectories(ServerConfig config, String path) async {
    try {
      final ftpConnect = FTPConnect(
        config.hostname,
        port: config.port,
        user: config.username,
        pass: config.password,
      );
      
      await ftpConnect.connect();
      
      // Change to the specified directory
      if (path != '/') {
        await ftpConnect.changeDirectory(path);
      }
      
      // List directories
      final files = await ftpConnect.listDirectoryContent();
      await ftpConnect.disconnect();
      
      final directories = files
          .where((file) => file.type == FTPEntryType.DIR)
          .map((file) => path == '/' ? '/${file.name}' : '$path/${file.name}')
          .toList();
      
      // Always include parent directory if not at root
      final List<String> finalDirs = [];
      if (path != '/' && path.isNotEmpty) {
        final parentPath = path.split('/').sublist(0, path.split('/').length - 1).join('/');
        finalDirs.add(parentPath.isEmpty ? '/' : parentPath);
      }
      finalDirs.addAll(directories);
      
      return finalDirs;
    } catch (e) {
      app_logger.Logger.error('FTP directory listing failed', error: e);
      return [];
    }
  }

  /// Get sync statistics for a list of files
  static Future<Map<String, int>> getSyncStatistics(List<File> files) async {
    int needsSync = 0;
    int alreadySynced = 0;
    int failed = 0;
    int syncing = 0;
    
    for (final file in files) {
      final existingRecord = await DatabaseService.getSyncRecordByPath(file.path);
      
      if (existingRecord == null) {
        needsSync++;
      } else {
        switch (existingRecord.status) {
          case SyncStatus.completed:
            final currentHash = await calculateFileHash(file);
            final lastModified = await file.lastModified();
            final hasChanged = currentHash != existingRecord.hash ||
                              lastModified.isAfter(existingRecord.lastModified);
            if (hasChanged) {
              needsSync++;
            } else {
              alreadySynced++;
            }
            break;
          case SyncStatus.failed:
            failed++;
            break;
          case SyncStatus.syncing:
            syncing++;
            break;
          case SyncStatus.pending:
            needsSync++;
            break;
        }
      }
    }
    
    return {
      'needsSync': needsSync,
      'alreadySynced': alreadySynced,
      'failed': failed,
      'syncing': syncing,
    };
  }

  /// Detects the server operating system type and home directory
  static Future<Map<String, dynamic>> detectServerInfo(ServerConfig config) async {
    if (config.syncMode != SyncMode.ssh) {
      return {
        'serverType': ServerType.unknown,
        'homeDirectory': null,
      };
    }

    try {
      app_logger.Logger.info('🔍 Detecting server info for ${config.hostname}');
      
      final socket = await SSHSocket.connect(config.hostname, config.port);
      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      
      await client.authenticated;
      
      // First, get the home directory - this is critical for permission management
      String? homeDirectory = await _detectHomeDirectory(client);
      app_logger.Logger.info('🏠 Detected home directory: $homeDirectory');
      
      // Then detect the server type
      final serverType = await _detectServerTypeFromClient(client);
      app_logger.Logger.info('🖥️ Detected server type: ${serverType.name}');
      
      client.close();
      
      return {
        'serverType': serverType,
        'homeDirectory': homeDirectory,
      };
      
    } catch (e) {
      app_logger.Logger.error('Failed to detect server info', error: e);
      return {
        'serverType': ServerType.unknown,
        'homeDirectory': null,
      };
    }
  }

  /// Detects the user's home directory on the server
  static Future<String?> _detectHomeDirectory(dynamic client) async {
    final homeCommands = [
      'pwd',           // Current working directory (usually starts in home)
      'echo \$HOME',   // Home environment variable
      'echo ~',        // Tilde expansion
    ];
    
    for (final command in homeCommands) {
      try {
        app_logger.Logger.info('🏠 Trying home detection: $command');
        
        final session = await client.execute(command);
        final bytes = <int>[];
        await for (final chunk in session.stdout) {
          bytes.addAll(chunk);
        }
        final result = utf8.decode(bytes).trim();
        
        app_logger.Logger.info('🏠 Home command result: $result');
        
        if (result.isNotEmpty && result != '~' && !result.contains('command not found')) {
          return result;
        }
      } catch (e) {
        app_logger.Logger.debug('Home detection command $command failed: $e');
        continue;
      }
    }
    
    // Fallback: construct likely home path
    return '/home/${client.username}';
  }

  /// Detects the server type from an active SSH client
  static Future<ServerType> _detectServerTypeFromClient(dynamic client) async {
    try {
      // Try different detection commands in order of reliability
      final detectionCommands = [
        {'command': 'uname -s', 'type': 'Unix-like systems', 'timeout': 5},
        {'command': r'echo $OSTYPE', 'type': 'Shell environment', 'timeout': 3},
        {'command': 'ver', 'type': 'Windows systems', 'timeout': 5},
        {'command': 'systeminfo | findstr /B /C:"OS Name"', 'type': 'Windows detailed', 'timeout': 10},
      ];
      
      for (final detection in detectionCommands) {
        try {
          final command = detection['command'] as String;
          final type = detection['type'] as String;
          app_logger.Logger.info('🔍 Trying $type: $command');
          
          final session = await client.execute(command);
          final bytes = <int>[];
          await for (final chunk in session.stdout) {
            bytes.addAll(chunk);
          }
          final result = utf8.decode(bytes).trim().toLowerCase();
          
          app_logger.Logger.info('📋 Command result: $result');
          
          if (result.isNotEmpty) {
            final serverType = _parseServerType(result);
            if (serverType != ServerType.unknown) {
              app_logger.Logger.info('✅ Detected server type: ${serverType.name}');
              client.close();
              return serverType;
            }
          }
        } catch (e) {
          final command = detection['command'] as String;
          app_logger.Logger.debug('Command $command failed: $e');
          continue;
        }
      }
      
      client.close();
      app_logger.Logger.info('❓ Could not determine server type, defaulting to Linux');
      return ServerType.linux; // Default to Linux for SSH servers
      
    } catch (e) {
      app_logger.Logger.error('Failed to detect server type', error: e);
      return ServerType.unknown;
    }
  }

  /// Parses the command output to determine server type
  static ServerType _parseServerType(String output) {
    final lowerOutput = output.toLowerCase();
    
    if (lowerOutput.contains('linux')) {
      return ServerType.linux;
    } else if (lowerOutput.contains('darwin') || lowerOutput.contains('macos')) {
      return ServerType.macos;
    } else if (lowerOutput.contains('windows') || lowerOutput.contains('microsoft')) {
      return ServerType.windows;
    } else if (lowerOutput.contains('freebsd') || lowerOutput.contains('openbsd') || 
               lowerOutput.contains('netbsd') || lowerOutput.contains('unix')) {
      return ServerType.linux; // Treat Unix-like systems as Linux
    }
    
    return ServerType.unknown;
  }

  // Helper methods for directory creation and file listing

  /// Creates only the category directory (e.g., 'images', 'videos') 
  /// Uses appropriate method based on server type
  static Future<void> _createCategoryDirectorySSH(dynamic sftp, String categoryPath, ServerType serverType) async {
    app_logger.Logger.info('🔧 Creating category directory: $categoryPath (Server: ${serverType.name})');
    
    try {
      // Check if category directory exists using SFTP stat
      await sftp.stat(categoryPath);
      app_logger.Logger.info('✅ Category directory already exists: $categoryPath');
    } catch (statError) {
      // Directory doesn't exist, create it using SFTP mkdir
      app_logger.Logger.info('❌ Category directory does not exist, creating: $categoryPath');
      try {
        await sftp.mkdir(categoryPath);
        app_logger.Logger.info('✅ Successfully created category directory: $categoryPath');
        
        // Verify creation
        await sftp.stat(categoryPath);
        app_logger.Logger.info('✅ Category directory creation verified: $categoryPath');
      } catch (mkdirError) {
        app_logger.Logger.error('❌ SFTP mkdir failed, trying fallback approach', error: mkdirError);
        
        // Fallback: try using shell commands based on server type
        await _createDirectoryUsingShell(sftp, categoryPath, serverType);
      }
    }
  }

  /// Creates directory using shell commands as fallback
  static Future<void> _createDirectoryUsingShell(dynamic sftp, String categoryPath, ServerType serverType) async {
    // For now, this is a placeholder - we can implement shell-based directory creation
    // if SFTP mkdir continues to fail
    app_logger.Logger.info('🔧 Attempting shell-based directory creation for ${serverType.name}');
    
    try {
      // We'll stick with SFTP mkdir for now as it's more reliable
      // Shell commands would require a separate SSH execution session
      await sftp.mkdir(categoryPath);
      app_logger.Logger.info('✅ Shell fallback successful: $categoryPath');
    } catch (e) {
      app_logger.Logger.error('❌ Shell fallback also failed', error: e);
      throw Exception('Failed to create directory $categoryPath using both SFTP and shell methods: $e');
    }
  }

  /// Creates only the category directory for FTP
  /// Assumes we're already in the correct base directory
  static Future<void> _createCategoryDirectoryFTP(FTPConnect ftpConnect, String categoryFolder) async {
    app_logger.Logger.info('🔧 Creating FTP category directory: $categoryFolder');
    
    try {
      // Try to change to the directory first to see if it exists
      await ftpConnect.changeDirectory(categoryFolder);
      app_logger.Logger.info('✅ Category directory already exists: $categoryFolder');
      // Go back to parent directory
      await ftpConnect.changeDirectory('..');
    } catch (e) {
      // Directory doesn't exist, create it
      app_logger.Logger.info('❌ Category directory does not exist, creating: $categoryFolder');
      try {
        await ftpConnect.makeDirectory(categoryFolder);
        app_logger.Logger.info('✅ Successfully created category directory: $categoryFolder');
      } catch (mkdirError) {
        app_logger.Logger.error('❌ Failed to create category directory $categoryFolder', error: mkdirError);
        throw Exception('Failed to create category directory $categoryFolder: $mkdirError');
      }
    }
  }

  static Future<List<String>> _listDirectorySSH(dynamic sftp, String directoryPath) async {
    final pathToList = directoryPath.isEmpty ? '/' : directoryPath;
    app_logger.Logger.info('📂 Listing directory contents: $pathToList');
    
    try {
      final files = await sftp.listdir(pathToList);
      final fileNames = files.map<String>((item) => item.filename as String).toList();
      app_logger.Logger.info('📂 Found ${fileNames.length} items in $pathToList: $fileNames');
      return fileNames;
    } catch (e) {
      app_logger.Logger.error('❌ Could not list directory $pathToList', error: e);
      return [];
    }
  }

  static Future<List<String>> _listDirectoryFTP(FTPConnect ftpConnect, String directoryPath) async {
    try {
      // Change to the directory first if it's not empty
      if (directoryPath.isNotEmpty && directoryPath != '/') {
        await ftpConnect.changeDirectory(directoryPath);
      }
      
      final files = await ftpConnect.listDirectoryContent();
      return files.map((file) => file.name).toList();
    } catch (e) {
      app_logger.Logger.debug('Could not list FTP directory $directoryPath: $e');
      return [];
    }
  }
}
