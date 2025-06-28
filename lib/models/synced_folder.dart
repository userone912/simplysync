import 'package:equatable/equatable.dart';

class SyncedFolder extends Equatable {
  final String id;
  final String localPath;
  final String name;
  final bool enabled;
  final bool autoDelete;

  const SyncedFolder({
    required this.id,
    required this.localPath,
    required this.name,
    this.enabled = true,
    this.autoDelete = false,
  });

  SyncedFolder copyWith({
    String? id,
    String? localPath,
    String? name,
    bool? enabled,
    bool? autoDelete,
  }) {
    return SyncedFolder(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      autoDelete: autoDelete ?? this.autoDelete,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localPath': localPath,
      'name': name,
      'enabled': enabled ? 1 : 0,
      'autoDelete': autoDelete ? 1 : 0,
    };
  }

  factory SyncedFolder.fromMap(Map<String, dynamic> map) {
    return SyncedFolder(
      id: map['id'] ?? '',
      localPath: map['localPath'] ?? '',
      name: map['name'] ?? '',
      enabled: (map['enabled'] ?? 1) == 1,
      autoDelete: (map['autoDelete'] ?? 0) == 1,
    );
  }

  @override
  List<Object?> get props => [id, localPath, name, enabled, autoDelete];
}
