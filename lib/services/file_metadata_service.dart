import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';

enum FileCategory {
  images,
  videos,
  documents,
  audio,
  archives,
  others
}

class FileMetadata {
  final String fileName;
  final String filePath;
  final FileCategory category;
  final String extension;
  final int size;
  final DateTime lastModified;

  const FileMetadata({
    required this.fileName,
    required this.filePath,
    required this.category,
    required this.extension,
    required this.size,
    required this.lastModified,
  });

  String get categoryFolder {
    switch (category) {
      case FileCategory.images:
        return 'images';
      case FileCategory.videos:
        return 'videos';
      case FileCategory.documents:
        return 'documents';
      case FileCategory.audio:
        return 'audio';
      case FileCategory.archives:
        return 'archives';
      case FileCategory.others:
        return 'others';
    }
  }
}

class FileMetadataService {
  static const Map<FileCategory, List<String>> _categoryExtensions = {
    FileCategory.images: [
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.tiff', '.ico', '.heic', '.raw'
    ],
    FileCategory.videos: [
      '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.mpg', '.mpeg'
    ],
    FileCategory.documents: [
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.odt', '.ods', '.odp'
    ],
    FileCategory.audio: [
      '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus'
    ],
    FileCategory.archives: [
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.tar.gz', '.tar.bz2'
    ]
  };

  /// Analyzes a file and returns its metadata including category
  static Future<FileMetadata> analyzeFile(File file) async {
    try {
      final fileName = path.basename(file.path);
      final extension = path.extension(file.path).toLowerCase();
      final stats = await file.stat();
      
      final category = _categorizeFile(extension);
      
      return FileMetadata(
        fileName: fileName,
        filePath: file.path,
        category: category,
        extension: extension,
        size: stats.size,
        lastModified: stats.modified,
      );
    } catch (e) {
      Logger.error('Failed to analyze file ${file.path}: $e');
      rethrow;
    }
  }

  /// Categorizes a file based on its extension
  static FileCategory _categorizeFile(String extension) {
    for (final category in _categoryExtensions.keys) {
      if (_categoryExtensions[category]!.contains(extension)) {
        return category;
      }
    }
    return FileCategory.others;
  }

  /// Generates a remote path for the file based on base path and category
  static String generateRemotePath(String basePath, FileMetadata metadata) {
    // Ensure base path ends with /
    String normalizedBasePath = basePath.endsWith('/') ? basePath : '$basePath/';
    return '${normalizedBasePath}${metadata.categoryFolder}/${metadata.fileName}';
  }

  /// Generates a unique filename if a conflict occurs
  static String generateUniqueFileName(String originalName, List<String> existingFiles) {
    if (!existingFiles.contains(originalName)) {
      return originalName;
    }

    final nameWithoutExt = path.basenameWithoutExtension(originalName);
    final extension = path.extension(originalName);
    
    int counter = 1;
    String newName;
    
    do {
      newName = '${nameWithoutExt}_$counter$extension';
      counter++;
    } while (existingFiles.contains(newName));
    
    return newName;
  }

  /// Checks if file type is supported for sync
  static bool isSupportedFileType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    // Check if file extension is in any of our supported categories
    for (final extensions in _categoryExtensions.values) {
      if (extensions.contains(extension)) {
        return true;
      }
    }
    
    // Also allow files without extension or unknown types
    return true;
  }

  /// Gets a human-readable description of the file category
  static String getCategoryDescription(FileCategory category) {
    switch (category) {
      case FileCategory.images:
        return 'Images';
      case FileCategory.videos:
        return 'Videos';
      case FileCategory.documents:
        return 'Documents';
      case FileCategory.audio:
        return 'Audio';
      case FileCategory.archives:
        return 'Archives';
      case FileCategory.others:
        return 'Others';
    }
  }

  /// Gets all supported file extensions for a category
  static List<String> getExtensionsForCategory(FileCategory category) {
    return _categoryExtensions[category] ?? [];
  }

  /// Gets all supported file extensions
  static List<String> getAllSupportedExtensions() {
    return _categoryExtensions.values.expand((extensions) => extensions).toList();
  }
}
