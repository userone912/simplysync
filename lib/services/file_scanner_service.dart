import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/synced_folder.dart';

class FileScannerService {
  static Future<List<File>> scanFoldersForFiles(List<SyncedFolder> folders) async {
    final List<File> allFiles = [];
    
    for (final folder in folders) {
      if (!folder.enabled) continue;
      
      try {
        final files = await scanFolder(folder.localPath);
        allFiles.addAll(files);
      } catch (e) {
        print('Error scanning folder ${folder.localPath}: $e');
      }
    }
    
    return allFiles;
  }

  static Future<List<File>> scanFolder(String folderPath) async {
    final List<File> files = [];
    final directory = Directory(folderPath);
    
    if (!await directory.exists()) {
      throw Exception('Directory does not exist: $folderPath');
    }
    
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          // Skip hidden files and system files
          if (!_shouldSkipFile(entity.path)) {
            files.add(entity);
          }
        }
      }
    } catch (e) {
      print('Error listing directory contents: $e');
      rethrow;
    }
    
    return files;
  }

  static bool _shouldSkipFile(String filePath) {
    final fileName = path.basename(filePath);
    
    // Skip hidden files
    if (fileName.startsWith('.')) return true;
    
    // Skip system files
    final systemFiles = [
      'Thumbs.db',
      'desktop.ini',
      '.DS_Store',
      '__MACOSX',
    ];
    
    if (systemFiles.contains(fileName)) return true;
    
    // Skip temporary files
    if (fileName.endsWith('.tmp') || 
        fileName.endsWith('.temp') || 
        fileName.startsWith('~')) {
      return true;
    }
    
    // Skip lock files
    if (fileName.endsWith('.lock')) return true;
    
    return false;
  }

  static Future<List<File>> getNewFiles(
    List<File> currentFiles, 
    List<String> previouslyScannedPaths,
  ) async {
    final currentPaths = currentFiles.map((f) => f.path).toSet();
    final previousPaths = previouslyScannedPaths.toSet();
    
    final newPaths = currentPaths.difference(previousPaths);
    
    return currentFiles.where((file) => newPaths.contains(file.path)).toList();
  }

  static Future<List<File>> getModifiedFiles(
    List<File> currentFiles,
    Map<String, DateTime> previousModificationTimes,
  ) async {
    final List<File> modifiedFiles = [];
    
    for (final file in currentFiles) {
      final previousModTime = previousModificationTimes[file.path];
      if (previousModTime == null) {
        // New file
        modifiedFiles.add(file);
      } else {
        final currentModTime = await file.lastModified();
        if (currentModTime.isAfter(previousModTime)) {
          // Modified file
          modifiedFiles.add(file);
        }
      }
    }
    
    return modifiedFiles;
  }

  static Future<Map<String, DateTime>> getFileModificationTimes(List<File> files) async {
    final Map<String, DateTime> modificationTimes = {};
    
    for (final file in files) {
      try {
        modificationTimes[file.path] = await file.lastModified();
      } catch (e) {
        print('Error getting modification time for ${file.path}: $e');
      }
    }
    
    return modificationTimes;
  }

  static Future<int> getFolderSize(String folderPath) async {
    int totalSize = 0;
    final directory = Directory(folderPath);
    
    if (!await directory.exists()) return 0;
    
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (e) {
            print('Error getting file size for ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      print('Error calculating folder size: $e');
    }
    
    return totalSize;
  }

  static Future<int> getFileCount(String folderPath) async {
    int fileCount = 0;
    final directory = Directory(folderPath);
    
    if (!await directory.exists()) return 0;
    
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File && !_shouldSkipFile(entity.path)) {
          fileCount++;
        }
      }
    } catch (e) {
      print('Error counting files: $e');
    }
    
    return fileCount;
  }

  static String formatFileSize(int bytes) {
    const int kb = 1024;
    const int mb = kb * 1024;
    const int gb = mb * 1024;
    
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }
}
