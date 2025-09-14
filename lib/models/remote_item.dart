import 'package:equatable/equatable.dart';

enum RemoteItemType { folder, file }

class RemoteItem extends Equatable {
  final String name;
  final String path;
  final RemoteItemType type;
  final int? size;
  final DateTime? lastModified;

  const RemoteItem({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.lastModified,
  });

  bool get isFolder => type == RemoteItemType.folder;
  bool get isFile => type == RemoteItemType.file;

  @override
  List<Object?> get props => [name, path, type, size, lastModified];

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'type': type.name,
      'size': size,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory RemoteItem.fromMap(Map<String, dynamic> map) {
    return RemoteItem(
      name: map['name'] ?? '',
      path: map['path'] ?? '',
      type: RemoteItemType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => RemoteItemType.file,
      ),
      size: map['size'],
      lastModified: map['lastModified'] != null 
          ? DateTime.tryParse(map['lastModified']) 
          : null,
    );
  }
}