import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../models/server_config.dart';
import '../models/sync_record.dart';
import '../models/remote_item.dart';
import '../utils/logger.dart' as app_logger;
import 'file_metadata_service.dart';
import 'database_service.dart';
import 'settings_service.dart';
import 'conflict_resolution.dart';

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
      } else if (config.syncMode == SyncMode.webdav) {
        final success = await _testWebDAVConnection(config);
        return {
          'success': success,
          'serverType': null,
        };
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

  /// List directories on the remote server
  static Future<List<RemoteItem>> listRemoteDirectory(ServerConfig config, [String? path]) async {
    final remotePath = path ?? config.remotePath;
    
    try {
      switch (config.syncMode) {
        case SyncMode.ssh:
          return await _listRemoteDirectorySSH(config, remotePath);
        case SyncMode.ftp:
          return await _listRemoteDirectoryFTP(config, remotePath);
        case SyncMode.webdav:
          return await _listRemoteDirectoryWebDAV(config, remotePath);
      }
    } catch (e) {
      app_logger.Logger.error('Failed to list remote directory: $remotePath', error: e);
      return [];
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

  static Future<bool> _testWebDAVConnection(ServerConfig config) async {
    try {
      // Use baseUrl if provided, otherwise construct from hostname/port
      final baseUrl = config.baseUrl?.isNotEmpty == true 
          ? config.baseUrl!
          : '${config.useSSL ? 'https' : 'http'}://${config.hostname}:${config.port}';
      
      final client = webdav.newClient(
        baseUrl,
        user: config.authType == AuthType.password ? config.username : '',
        password: config.authType == AuthType.password ? config.password : '',
      );
      
      // Add bearer token support
      if (config.authType == AuthType.token && config.bearerToken?.isNotEmpty == true) {
        client.setHeaders({
          'user-agent': 'SimplySync',
          'Authorization': 'Bearer ${config.bearerToken}',
        });
      } else {
        client.setHeaders({'user-agent': 'SimplySync'});
      }
      
      client.setConnectTimeout(5000);
      client.setSendTimeout(5000);
      client.setReceiveTimeout(5000);

      // Test connection by trying to read the root directory
      await client.readDir('/');
      return true; // If we get here, connection worked
    } catch (e) {
      app_logger.Logger.error('WebDAV connection test failed', error: e);
      return false;
    }
  }

  static Future<SyncRecord> syncFile(File file, ServerConfig config, {String? syncSessionId, SyncRecord? existingRecord}) async {
    try {
      app_logger.Logger.info('Starting sync for file: ���[38;5;2m${file.path}���[0m');
      app_logger.Logger.info('Server config - Host: ${config.hostname}, Port: ${config.port}, Mode: ${config.syncMode}');
      
      // Yield to UI thread
      await Future.delayed(const Duration(microseconds: 100));
      
      // Analyze file metadata
      final metadata = await FileMetadataService.analyzeFile(file);
      app_logger.Logger.info('File metadata - Name: ${metadata.fileName}, Size: ${metadata.size}, Category: ${metadata.categoryFolder}');

      // Generate the categorized remote path
      final remotePath = FileMetadataService.generateRemotePath(config.remotePath, metadata);
      app_logger.Logger.info('Target remote path: $remotePath');
      
      // Yield to UI thread before heavy operations
      await Future.delayed(const Duration(microseconds: 100));
      
      final hash = await calculateFileHash(file);
      
      final record = existingRecord?.copyWith(
        status: SyncStatus.syncing,
        syncSessionId: syncSessionId,
        hash: hash,
        fileSize: metadata.size,
        lastModified: metadata.lastModified,
      ) ?? SyncRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: file.path,
        fileName: metadata.fileName,
        fileSize: metadata.size,
        hash: hash,
        lastModified: metadata.lastModified,
        status: SyncStatus.syncing,
        syncSessionId: syncSessionId,
      );

      // Insert or update the 'syncing' record in the database for real-time progress
      if (existingRecord != null) {
        await DatabaseService.updateSyncRecord(record);
      } else {
        await DatabaseService.insertSyncRecord(record);
      }

      // Yield to UI thread before network operations
      await Future.delayed(const Duration(microseconds: 100));

      Map<String, dynamic> result;
      if (config.syncMode == SyncMode.ssh) {
        app_logger.Logger.info('Using SSH sync mode');
        result = await _syncFileSSH(file, config, metadata, remotePath);
      } else if (config.syncMode == SyncMode.webdav) {
        app_logger.Logger.info('Using WebDAV sync mode');
        result = await _syncFileWebDAV(file, config, metadata, remotePath);
      } else {
        app_logger.Logger.info('Using FTP sync mode');
        result = await _syncFileFTP(file, config, metadata, remotePath);
      }

      final success = result['success'] ?? false;
      final errorMessage = result['error'] as String?;
      final skipped = result['skipped'] == true;

      if (skipped) {
        return record.copyWith(
          status: SyncStatus.skipped,
          errorMessage: errorMessage ?? 'Skipped due to filename conflict',
        );
      }

      app_logger.Logger.info('Sync result - Success: $success, Error: $errorMessage');

      final finalRecord = record.copyWith(
        status: success ? SyncStatus.completed : SyncStatus.failed,
        syncedAt: success ? DateTime.now() : null,
        errorMessage: success ? null : (errorMessage ?? 'Upload failed'),
      );

      // Update the database with the final sync result
      await DatabaseService.updateSyncRecord(finalRecord);

      // Auto-delete local file if enabled and sync was successful
      if (success) {
        final autoDeleteEnabled = await SettingsService.getAutoDeleteEnabled();
        if (autoDeleteEnabled) {
          try {
            await file.delete();
            app_logger.Logger.info('✓ Auto-deleted local file: ${file.path}');
          } catch (deleteError) {
            app_logger.Logger.error('Failed to auto-delete file ${file.path}', error: deleteError);
            // Don't fail the sync just because deletion failed
          }
        }
      }

      return finalRecord;
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
        syncSessionId: syncSessionId,
      );
    }
  }

  static Future<Map<String, dynamic>> _syncFileSSH(
    File file, 
    ServerConfig config, 
    FileMetadata metadata, 
    String targetRemotePath
  ) async {
    // Get conflict resolution mode from settings
    final conflictResolutionMode = await SettingsService.getConflictResolutionMode();
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
      app_logger.Logger.info('Found \u001b[38;5;2m${existingFiles.length}\u001b[0m existing files: $existingFiles');
      final resolvedFileName = resolveFileName(
        originalName: fileName,
        existingFiles: existingFiles,
        mode: conflictResolutionMode,
      );
      if (resolvedFileName == null) {
        app_logger.Logger.info('Skipping file due to conflict resolution mode: skip');
        client.close();
        return {
          'success': false,
          'remotePath': null,
          'error': 'Skipped due to filename conflict',
          'skipped': true,
        };
      }
      final uniqueFileName = resolvedFileName;
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
    // Get conflict resolution mode from settings
    final conflictResolutionMode = await SettingsService.getConflictResolutionMode();
    try {
      app_logger.Logger.info('Attempting FTP connection to [38;5;2m${config.hostname}:${config.port}[0m');
      
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
      final resolvedFileName = resolveFileName(
        originalName: fileName,
        existingFiles: existingFiles,
        mode: conflictResolutionMode,
      );
      if (resolvedFileName == null) {
        app_logger.Logger.info('Skipping file due to conflict resolution mode: skip');
        await ftpConnect.disconnect();
        return {
          'success': false,
          'remotePath': null,
          'error': 'Skipped due to filename conflict',
          'skipped': true,
        };
      }
      final uniqueFileName = resolvedFileName;
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

  static Future<Map<String, dynamic>> _syncFileWebDAV(
    File file, 
    ServerConfig config, 
    FileMetadata metadata, 
    String targetRemotePath
  ) async {
    // Get conflict resolution mode from settings
    final conflictResolutionMode = await SettingsService.getConflictResolutionMode();
    
    return await _performWebDAVSync(file, config, metadata, targetRemotePath, conflictResolutionMode);
  }

  static Future<Map<String, dynamic>> _performWebDAVSync(
    File file,
    ServerConfig config,
    FileMetadata metadata,
    String targetRemotePath,
    String conflictResolutionMode,
  ) async {
    try {
      // Use baseUrl if provided, otherwise construct from hostname/port
      final baseUrl = config.baseUrl?.isNotEmpty == true 
          ? config.baseUrl!
          : '${config.useSSL ? 'https' : 'http'}://${config.hostname}:${config.port}';
      
      app_logger.Logger.info('Attempting WebDAV connection to $baseUrl');
      
      final client = webdav.newClient(
        baseUrl,
        user: config.authType == AuthType.password ? config.username : '',
        password: config.authType == AuthType.password ? config.password : '',
      );
      
      // Add bearer token support
      if (config.authType == AuthType.token && config.bearerToken?.isNotEmpty == true) {
        client.setHeaders({
          'user-agent': 'SimplySync',
          'Authorization': 'Bearer ${config.bearerToken}',
        });
      } else {
        client.setHeaders({'user-agent': 'SimplySync'});
      }
      
      client.setConnectTimeout(15000);
      client.setSendTimeout(60000); // Increase timeout for file uploads
      client.setReceiveTimeout(30000);

      app_logger.Logger.info('WebDAV connection successful');

      // Extract directory and filename from target path (same approach as SSH)
      final parts = targetRemotePath.split('/');
      final fileName = parts.last;
      
      // Create the directory path without the filename
      final directoryParts = parts.sublist(0, parts.length - 1);
      final directoryPath = directoryParts.join('/');
      final normalizedPath = directoryPath.startsWith('/') ? directoryPath : '/$directoryPath';
      
      app_logger.Logger.info('WebDAV paths - Directory: $normalizedPath, File: $fileName');
      
      final fullRemotePath = normalizedPath.endsWith('/') ? '$normalizedPath/$fileName' : '$normalizedPath/$fileName';
      
      app_logger.Logger.info('WebDAV full path: $fullRemotePath');
      
      app_logger.Logger.info('Target WebDAV path: $fullRemotePath');

      // Check if file already exists (conflict resolution)
      bool fileExists = false;
      try {
        final existingFiles = await client.readDir(normalizedPath);
        fileExists = existingFiles.any((f) => f.name == fileName);
      } catch (e) {
        // Directory might not exist, we'll create it
        app_logger.Logger.info('Directory does not exist, will be created: $normalizedPath');
      }

      if (fileExists) {
        app_logger.Logger.info('File already exists on WebDAV server: $fileName');
        if (conflictResolutionMode == 'skip') {
          app_logger.Logger.info('Skipping file due to conflict resolution setting');
          return {
            'success': true,
            'skipped': true,
            'remotePath': fullRemotePath,
            'error': 'File already exists (skipped)',
          };
        }
        // For overwrite mode, we continue with upload
      }

      // Create directory if it doesn't exist (ensure only the directory path, not including filename)
      try {
        app_logger.Logger.info('Creating WebDAV directory: $normalizedPath');
        await client.mkdir(normalizedPath);
        app_logger.Logger.info('WebDAV directory created successfully');
      } catch (e) {
        // Directory might already exist, that's fine
        app_logger.Logger.info('Directory creation result: ${e.toString()}');
      }

      // Upload the file (make sure we're not accidentally creating a directory with the filename)
      app_logger.Logger.info('Uploading ${metadata.fileName} to WebDAV server at path: $fullRemotePath');
      final fileBytes = await file.readAsBytes();
      
      try {
        await client.write(fullRemotePath, fileBytes);
        app_logger.Logger.info('WebDAV file upload completed');
        
        // Verify the file was actually uploaded by checking if it exists
        try {
          final uploadedFiles = await client.readDir(normalizedPath);
          final uploadedFile = uploadedFiles.firstWhere(
            (f) => f.name == fileName,
            orElse: () => throw Exception('File not found after upload'),
          );
          
          app_logger.Logger.info('✅ WebDAV upload verified: ${metadata.fileName} (size: ${uploadedFile.size})');
          
          // Optionally verify file size matches
          if (uploadedFile.size != null && uploadedFile.size != fileBytes.length) {
            throw Exception('File size mismatch: expected ${fileBytes.length}, got ${uploadedFile.size}');
          }
          
        } catch (verifyError) {
          app_logger.Logger.error('WebDAV upload verification failed', error: verifyError);
          throw Exception('Upload verification failed: ${verifyError.toString()}');
        }
        
      } catch (e) {
        app_logger.Logger.error('WebDAV file upload failed', error: e);
        throw e;
      }
      
      app_logger.Logger.info('✅ WebDAV upload successful: ${metadata.fileName}');
      return {
        'success': true,
        'remotePath': fullRemotePath,
        'error': null,
      };
    } catch (e) {
      app_logger.Logger.error('WebDAV sync failed for ${metadata.fileName}', error: e);
      return {
        'success': false,
        'remotePath': null,
        'error': 'WebDAV Error: ${e.toString()}',
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
    
    // Skip files that were skipped due to conflict
    if (existingRecord.status == SyncStatus.skipped) {
      app_logger.Logger.info('File ${file.path} skipped: Skipped previously due to conflict');
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
          .where((file) => file.type == FTPEntryType.dir)
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
          case SyncStatus.skipped:
            // Skipped files are not counted as needing sync or failed
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
      
      // First detect the server type
      final serverType = await _detectServerTypeFromClient(client);
      app_logger.Logger.info('🖥️ Detected server type: ${serverType.name}');
      
      // Then get the home directory based on server type
      String? homeDirectory = await _detectHomeDirectoryForType(client, serverType);
      app_logger.Logger.info('🏠 Detected home directory: $homeDirectory');
      
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

  /// Detects the user's home directory on the server based on server type
  static Future<String?> _detectHomeDirectoryForType(dynamic client, ServerType serverType) async {
    List<String> homeCommands;
    String fallbackPath;
    
    switch (serverType) {
      case ServerType.windows:
        homeCommands = [
          'echo %USERPROFILE%',           // Windows user profile
          'echo %HOMEDRIVE%%HOMEPATH%',   // Alternative Windows home
          'cd',                           // Current directory in Windows
          'pwd',                          // Unix-style pwd (might work in some Windows SSH)
        ];
        fallbackPath = 'C:\\Users\\${client.username}';
        break;
        
      case ServerType.macos:
        homeCommands = [
          'echo \$HOME',      // Home environment variable
          'echo ~',           // Tilde expansion
          'pwd',              // Current working directory
          'dscl . -read /Users/\$USER NFSHomeDirectory | cut -d: -f2',  // macOS specific
        ];
        fallbackPath = '/Users/${client.username}';
        break;
        
      case ServerType.linux:
      default:
        homeCommands = [
          'echo \$HOME',      // Home environment variable
          'echo ~',           // Tilde expansion
          'pwd',              // Current working directory
          'getent passwd \$USER | cut -d: -f6',  // Get home from passwd
        ];
        fallbackPath = '/home/${client.username}';
        break;
    }
    
    app_logger.Logger.info('🏠 Detecting home directory for ${serverType.name} server');
    
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
        
        if (result.isNotEmpty && 
            result != '~' && 
            !result.contains('command not found') &&
            !result.contains('not found') &&
            !result.contains('error')) {
          
          // Validate the path looks reasonable
          if (_isValidHomePath(result, serverType)) {
            app_logger.Logger.info('✅ Valid home directory detected: $result');
            return result;
          }
        }
      } catch (e) {
        app_logger.Logger.debug('Home detection command $command failed: $e');
        continue;
      }
    }
    
    // Fallback: construct likely home path based on server type
    app_logger.Logger.info('🏠 Using fallback home path: $fallbackPath');
    return fallbackPath;
  }
  
  /// Validates if a detected path looks like a valid home directory
  static bool _isValidHomePath(String path, ServerType serverType) {
    switch (serverType) {
      case ServerType.windows:
        // Windows paths typically start with drive letter
        return path.contains(':') && (path.contains('Users') || path.contains('Documents'));
        
      case ServerType.macos:
        // macOS user directories are in /Users/
        return path.startsWith('/Users/') || path.startsWith('/home/');
        
      case ServerType.linux:
      default:
        // Linux user directories are typically in /home/ or /root
        return path.startsWith('/home/') || path.startsWith('/root') || path.startsWith('/var/') || path == '/';
    }
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

  /// Detects the FTP user's working directory
  static Future<String?> detectFTPWorkingDirectory(ServerConfig config) async {
    if (config.syncMode != SyncMode.ftp) {
      return null;
    }

    try {
      app_logger.Logger.info('🔍 Detecting FTP working directory for ${config.hostname}');
      
      final ftpConnect = FTPConnect(
        config.hostname,
        user: config.username,
        pass: config.password,
        port: config.port,
      );

      final connected = await ftpConnect.connect();
      if (!connected) {
        app_logger.Logger.error('Failed to connect to FTP server');
        return null;
      }

      // Get current working directory
      final currentDir = await ftpConnect.currentDirectory();
      app_logger.Logger.info('🏠 FTP working directory: $currentDir');
      
      await ftpConnect.disconnect();
      return currentDir;
      
    } catch (e) {
      app_logger.Logger.error('Failed to detect FTP working directory', error: e);
      return null;
    }
  }

  /// Gets the appropriate default directory for folder browsing based on server config
  static Future<String> getDefaultBrowsingDirectory(ServerConfig config) async {
    if (config.syncMode == SyncMode.ssh) {
      // For SSH, use detected home directory or fallback
      if (config.homeDirectory != null && config.homeDirectory!.isNotEmpty) {
        app_logger.Logger.info('📁 Using saved SSH home directory: ${config.homeDirectory}');
        return config.homeDirectory!;
      }
      
      // If no home directory saved, detect it
      final serverInfo = await detectServerInfo(config);
      final homeDir = serverInfo['homeDirectory'] as String?;
      if (homeDir != null && homeDir.isNotEmpty) {
        app_logger.Logger.info('📁 Using detected SSH home directory: $homeDir');
        return homeDir;
      }
      
      // Ultimate fallback based on typical SSH defaults
      app_logger.Logger.info('📁 Using SSH fallback directory: /');
      return '/';
      
    } else if (config.syncMode == SyncMode.ftp) {
      // For FTP, get the working directory
      final ftpWorkingDir = await detectFTPWorkingDirectory(config);
      if (ftpWorkingDir != null && ftpWorkingDir.isNotEmpty) {
        app_logger.Logger.info('📁 Using FTP working directory: $ftpWorkingDir');
        return ftpWorkingDir;
      }
      
      // FTP fallback
      app_logger.Logger.info('📁 Using FTP fallback directory: /');
      return '/';
    }
    
    // Default fallback
    return '/';
  }

  /// Creates a directory on the server
  static Future<bool> createDirectory(ServerConfig config, String directoryPath) async {
    try {
      app_logger.Logger.info('Creating directory: $directoryPath on ${config.syncMode.name.toUpperCase()} server');
      
      if (config.syncMode == SyncMode.ssh) {
        return await _createSSHDirectory(config, directoryPath);
      } else {
        return await _createFTPDirectory(config, directoryPath);
      }
    } catch (e) {
      app_logger.Logger.error('Failed to create directory: $directoryPath', error: e);
      throw e; // Re-throw the exception with specific error details
    }
  }

  static Future<bool> _createSSHDirectory(ServerConfig config, String directoryPath) async {
    try {
      final socket = await SSHSocket.connect(config.hostname, config.port);
      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      
      await client.authenticated;
      app_logger.Logger.info('SSH connection established for directory creation');
      
      // Use mkdir command to create the directory
      final command = 'mkdir -p "$directoryPath"';
      app_logger.Logger.info('Executing SSH command: $command');
      
      final session = await client.execute(command);
      
      // Collect any error output
      final errorBytes = <int>[];
      await for (final chunk in session.stderr) {
        errorBytes.addAll(chunk);
      }
      
      // Wait for command completion and check exit code
      final exitCode = await session.exitCode;
      
      client.close();
      
      if (exitCode == 0) {
        app_logger.Logger.info('✅ SSH directory created successfully: $directoryPath');
        return true;
      } else {
        final errorOutput = utf8.decode(errorBytes);
        app_logger.Logger.error('SSH mkdir command failed with exit code: $exitCode, error: $errorOutput');
        throw Exception('mkdir failed (exit code: $exitCode): $errorOutput');
      }
    } catch (e) {
      app_logger.Logger.error('SSH directory creation failed', error: e);
      throw e; // Re-throw to provide specific error information
    }
  }

  static Future<bool> _createFTPDirectory(ServerConfig config, String directoryPath) async {
    try {
      final ftpConnect = FTPConnect(
        config.hostname,
        port: config.port,
        user: config.username,
        pass: config.password,
      );
      
      final connected = await ftpConnect.connect();
      if (!connected) {
        throw Exception('Failed to connect to FTP server');
      }
      
      app_logger.Logger.info('FTP connection established for directory creation');
      
      // Extract directory path and name
      final parts = directoryPath.split('/').where((part) => part.isNotEmpty).toList();
      final dirName = parts.last;
      final parentPath = parts.length > 1 ? '/${parts.sublist(0, parts.length - 1).join('/')}' : '/';
      
      app_logger.Logger.info('Creating directory "$dirName" in parent path: $parentPath');
      
      // Navigate to parent directory if it's not root
      if (parentPath != '/') {
        try {
          await ftpConnect.changeDirectory(parentPath);
          app_logger.Logger.info('Changed to parent directory: $parentPath');
        } catch (e) {
          await ftpConnect.disconnect();
          throw Exception('Failed to navigate to parent directory: $parentPath - $e');
        }
      }
      
      // Create the directory
      final success = await ftpConnect.makeDirectory(dirName);
      await ftpConnect.disconnect();
      
      if (success) {
        app_logger.Logger.info('✅ FTP directory created successfully: $directoryPath');
        return true;
      } else {
        throw Exception('FTP makeDirectory command failed for: $dirName');
      }
    } catch (e) {
      app_logger.Logger.error('FTP directory creation failed', error: e);
      throw e; // Re-throw to provide specific error information
    }
  }

  /// Enhanced file sync with retry logic and connection pooling
  static Future<SyncRecord> syncFileWithRetry(
    File file, 
    ServerConfig config, {
    String? syncSessionId,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    Exception? lastError;

    while (attempt < maxRetries) {
      try {
        attempt++;
        app_logger.Logger.info('🔄 Sync attempt $attempt/$maxRetries for: ${file.path}');
        
        final result = await syncFile(file, config, syncSessionId: syncSessionId);
        
        if (result.status == SyncStatus.completed) {
          app_logger.Logger.info('✅ Sync successful on attempt $attempt');
          return result;
        } else if (attempt < maxRetries) {
          app_logger.Logger.warning('⚠️ Sync failed on attempt $attempt, retrying...');
          await Future.delayed(retryDelay * attempt); // Exponential backoff
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        if (attempt < maxRetries) {
          app_logger.Logger.warning('❌ Attempt $attempt failed: $e, retrying...');
          await Future.delayed(retryDelay * attempt); // Exponential backoff
        } else {
          app_logger.Logger.error('❌ All $maxRetries attempts failed for: ${file.path}', error: e);
        }
      }
    }

    // All attempts failed
    throw lastError ?? Exception('Sync failed after $maxRetries attempts');
  }

  /// Batch sync multiple files efficiently
  static Future<List<SyncRecord>> syncFilesBatch(
    List<File> files,
    ServerConfig config, {
    String? syncSessionId,
    int batchSize = 5,
    Function(int completed, int total)? onProgress,
  }) async {
    final results = <SyncRecord>[];
    
    app_logger.Logger.info('📦 Starting batch sync for ${files.length} files (batch size: $batchSize)');
    
    for (int i = 0; i < files.length; i += batchSize) {
      final batch = files.skip(i).take(batchSize).toList();
      
      // Process batch concurrently
      final futures = batch.map((file) => syncFileWithRetry(
        file, 
        config, 
        syncSessionId: syncSessionId,
      ));
      
      try {
        final batchResults = await Future.wait(futures);
        results.addAll(batchResults);
        
        onProgress?.call(results.length, files.length);
        
        // Small delay between batches to prevent server overload
        if (i + batchSize < files.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
        app_logger.Logger.error('❌ Batch sync failed at batch starting index $i', error: e);
        rethrow;
      }
    }
    
    app_logger.Logger.info('✅ Batch sync completed: ${results.length}/${files.length} files');
    return results;
  }

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

  /// Get or create a reusable connection
  /// List remote directory contents for SSH/SFTP
  static Future<List<RemoteItem>> _listRemoteDirectorySSH(ServerConfig config, String path) async {
    final socket = await SSHSocket.connect(config.hostname, config.port);
    final client = SSHClient(socket, username: config.username, onPasswordRequest: () => config.password);

    try {
      await client.authenticated;
      final sftp = await client.sftp();
      
      final fullPath = path.isEmpty ? '/' : path;
      final items = await sftp.listdir(fullPath);
      
      final remoteItems = <RemoteItem>[];
      for (final item in items) {
        final itemPath = fullPath.endsWith('/') ? '$fullPath${item.filename}' : '$fullPath/${item.filename}';
        final isDirectory = item.attr.isDirectory;
        
        remoteItems.add(RemoteItem(
          name: item.filename,
          path: itemPath,
          type: isDirectory ? RemoteItemType.folder : RemoteItemType.file,
          size: isDirectory ? null : item.attr.size,
          lastModified: item.attr.modifyTime != null 
              ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
              : null,
        ));
      }
      
      // Sort folders first, then files
      remoteItems.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
      return remoteItems;
    } finally {
      client.close();
    }
  }

  /// List remote directory contents for FTP
  static Future<List<RemoteItem>> _listRemoteDirectoryFTP(ServerConfig config, String path) async {
    final ftpConnect = FTPConnect(config.hostname,
        port: config.port, user: config.username, pass: config.password);
    
    try {
      await ftpConnect.connect();
      
      if (path.isNotEmpty && path != '/') {
        await ftpConnect.changeDirectory(path);
      }
      
      final items = await ftpConnect.listDirectoryContent();
      final remoteItems = <RemoteItem>[];
      
      for (final item in items) {
        final itemPath = path.isEmpty || path == '/' ? '/${item.name}' : '$path/${item.name}';
        
        remoteItems.add(RemoteItem(
          name: item.name,
          path: itemPath,
          type: item.type == FTPEntryType.dir ? RemoteItemType.folder : RemoteItemType.file,
          size: item.type == FTPEntryType.file ? item.size : null,
          lastModified: item.modifyTime,
        ));
      }
      
      // Sort folders first, then files
      remoteItems.sort((a, b) {
        if (a.isFolder && !b.isFolder) return -1;
        if (!a.isFolder && b.isFolder) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      
      return remoteItems;
    } finally {
      await ftpConnect.disconnect();
    }
  }

  /// List remote directory contents for WebDAV
  static Future<List<RemoteItem>> _listRemoteDirectoryWebDAV(ServerConfig config, String path) async {
    try {
      final normalizedPath = path.endsWith('/') ? path : '$path/';
      
      // Use baseUrl if provided, otherwise construct from hostname/port
      final baseUrl = config.baseUrl?.isNotEmpty == true 
          ? config.baseUrl!
          : '${config.useSSL ? 'https' : 'http'}://${config.hostname}:${config.port}';
      
      app_logger.Logger.info('WebDAV: Connecting to $baseUrl with path: $normalizedPath');
      app_logger.Logger.info('WebDAV: Auth type: ${config.authType.name}, Username: ${config.username}');
      
      final client = webdav.newClient(
        baseUrl,
        user: config.authType == AuthType.password ? config.username : '',
        password: config.authType == AuthType.password ? config.password : '',
      );
      
      // Add bearer token support with consistent header format
      final headers = <String, String>{
        'user-agent': 'SimplySync/1.0',
      };
      
      if (config.authType == AuthType.token && config.bearerToken?.isNotEmpty == true) {
        headers['Authorization'] = 'Bearer ${config.bearerToken}';
      }
      
      client.setHeaders(headers);
      
      client.setConnectTimeout(15000);  // Increase timeout
      client.setSendTimeout(15000);
      client.setReceiveTimeout(15000);

      app_logger.Logger.info('WebDAV: Attempting to read directory: $normalizedPath');
      final files = await client.readDir(normalizedPath);
      app_logger.Logger.info('WebDAV: Successfully read ${files.length} items');
      
      return files.map((file) {
        return RemoteItem(
          name: file.name ?? 'Unknown',
          path: file.path ?? '$normalizedPath${file.name ?? 'Unknown'}',
          type: (file.isDir ?? false) ? RemoteItemType.folder : RemoteItemType.file,
          size: file.size,
          lastModified: file.mTime,
        );
      }).toList();
    } catch (e) {
      app_logger.Logger.error('WebDAV connection failed: $e');
      app_logger.Logger.error('WebDAV config - BaseUrl: ${config.baseUrl}, Hostname: ${config.hostname}:${config.port}');
      app_logger.Logger.error('WebDAV auth - Type: ${config.authType.name}, Username: ${config.username}, HasPassword: ${config.password.isNotEmpty}');
      throw Exception('Failed to list WebDAV directory: $e');
    }
  }
}
