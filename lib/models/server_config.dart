import 'package:equatable/equatable.dart';

enum SyncMode { ssh, ftp }

enum ServerType { 
  linux, 
  windows, 
  macos, 
  unknown 
}

class ServerConfig extends Equatable {
  final SyncMode syncMode;
  final String hostname;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final ServerType? serverType; // Detected server type for SSH
  final String? homeDirectory; // User's home directory on the server

  const ServerConfig({
    required this.syncMode,
    required this.hostname,
    required this.port,
    required this.username,
    required this.password,
    this.remotePath = '/',
    this.serverType,
    this.homeDirectory,
  });

  ServerConfig copyWith({
    SyncMode? syncMode,
    String? hostname,
    int? port,
    String? username,
    String? password,
    String? remotePath,
    ServerType? serverType,
    String? homeDirectory,
  }) {
    return ServerConfig(
      syncMode: syncMode ?? this.syncMode,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      serverType: serverType ?? this.serverType,
      homeDirectory: homeDirectory ?? this.homeDirectory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'syncMode': syncMode.name,
      'hostname': hostname,
      'port': port,
      'username': username,
      'password': password,
      'remotePath': remotePath,
      'serverType': serverType?.name,
      'homeDirectory': homeDirectory,
    };
  }

  factory ServerConfig.fromMap(Map<String, dynamic> map) {
    return ServerConfig(
      syncMode: SyncMode.values.firstWhere(
        (e) => e.name == map['syncMode'],
        orElse: () => SyncMode.ssh,
      ),
      hostname: map['hostname'] ?? '',
      port: map['port'] ?? 22,
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      remotePath: map['remotePath'] ?? '/',
      serverType: map['serverType'] != null
          ? ServerType.values.firstWhere(
              (e) => e.name == map['serverType'],
              orElse: () => ServerType.unknown,
            )
          : null,
      homeDirectory: map['homeDirectory'],
    );
  }

  @override
  List<Object?> get props => [
        syncMode,
        hostname,
        port,
        username,
        password,
        remotePath,
        serverType,
        homeDirectory,
      ];
}
