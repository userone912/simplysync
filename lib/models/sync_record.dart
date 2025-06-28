import 'package:equatable/equatable.dart';

enum SyncStatus { pending, syncing, completed, failed }

class SyncRecord extends Equatable {
  final String id;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String hash;
  final DateTime lastModified;
  final DateTime? syncedAt;
  final SyncStatus status;
  final String? errorMessage;
  final bool deleted;

  const SyncRecord({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.hash,
    required this.lastModified,
    this.syncedAt,
    this.status = SyncStatus.pending,
    this.errorMessage,
    this.deleted = false,
  });

  SyncRecord copyWith({
    String? id,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? hash,
    DateTime? lastModified,
    DateTime? syncedAt,
    SyncStatus? status,
    String? errorMessage,
    bool? deleted,
  }) {
    return SyncRecord(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      hash: hash ?? this.hash,
      lastModified: lastModified ?? this.lastModified,
      syncedAt: syncedAt ?? this.syncedAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'hash': hash,
      'lastModified': lastModified.millisecondsSinceEpoch,
      'syncedAt': syncedAt?.millisecondsSinceEpoch,
      'status': status.name,
      'errorMessage': errorMessage,
      'deleted': deleted ? 1 : 0,
    };
  }

  factory SyncRecord.fromMap(Map<String, dynamic> map) {
    return SyncRecord(
      id: map['id'] ?? '',
      filePath: map['filePath'] ?? '',
      fileName: map['fileName'] ?? '',
      fileSize: map['fileSize'] ?? 0,
      hash: map['hash'] ?? '',
      lastModified: DateTime.fromMillisecondsSinceEpoch(map['lastModified']),
      syncedAt: map['syncedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['syncedAt'])
          : null,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SyncStatus.pending,
      ),
      errorMessage: map['errorMessage'],
      deleted: map['deleted'] == 1,
    );
  }

  @override
  List<Object?> get props => [
        id,
        filePath,
        fileName,
        fileSize,
        hash,
        lastModified,
        syncedAt,
        status,
        errorMessage,
        deleted,
      ];
}
