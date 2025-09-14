import 'file_metadata_service.dart';

/// Supported conflict resolution modes
enum ConflictResolutionMode { append, overwrite, skip }

extension ConflictResolutionModeExt on ConflictResolutionMode {
  static ConflictResolutionMode fromString(String mode) {
    switch (mode) {
      case 'overwrite':
        return ConflictResolutionMode.overwrite;
      case 'skip':
        return ConflictResolutionMode.skip;
      case 'append':
      default:
        return ConflictResolutionMode.append;
    }
  }

  String get name => toString().split('.').last;
}

/// Returns the resolved filename or null if the file should be skipped
String? resolveFileName({
  required String originalName,
  required List<String> existingFiles,
  required String mode,
}) {
  final conflictMode = ConflictResolutionModeExt.fromString(mode);
  switch (conflictMode) {
    case ConflictResolutionMode.overwrite:
      return originalName;
    case ConflictResolutionMode.skip:
      if (existingFiles.contains(originalName)) {
        return null; // skip
      }
      return originalName;
    case ConflictResolutionMode.append:
      return FileMetadataService.generateUniqueFileName(originalName, existingFiles);
  }
}
