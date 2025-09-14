import 'package:equatable/equatable.dart';

enum SyncMode { ssh, ftp, webdav }

enum ServerType { 
  linux, 
  windows, 
  macos, 
  unknown 
}

enum AuthType { 
  password,    // Username/password 
  token,       // Bearer token (for WebDAV)
  key         // SSH key (future)
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
  
  // Protocol-specific settings
  final bool useSSL;           // For FTP (FTPS) and WebDAV (HTTPS)
  final AuthType authType;     // Authentication method
  final String? bearerToken;   // For WebDAV token auth
  final String? baseUrl;       // Full URL for WebDAV (overrides hostname:port if provided)

  const ServerConfig({
    required this.syncMode,
    required this.hostname,
    required this.port,
    required this.username,
    required this.password,
    this.remotePath = '/',
    this.serverType,
    this.homeDirectory,
    this.useSSL = false,
    this.authType = AuthType.password,
    this.bearerToken,
    this.baseUrl,
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
    bool? useSSL,
    AuthType? authType,
    String? bearerToken,
    String? baseUrl,
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
      useSSL: useSSL ?? this.useSSL,
      authType: authType ?? this.authType,
      bearerToken: bearerToken ?? this.bearerToken,
      baseUrl: baseUrl ?? this.baseUrl,
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
      'useSSL': useSSL,
      'authType': authType.name,
      'bearerToken': bearerToken,
      'baseUrl': baseUrl,
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
      useSSL: map['useSSL'] ?? false,
      authType: map['authType'] != null
          ? AuthType.values.firstWhere(
              (e) => e.name == map['authType'],
              orElse: () => AuthType.password,
            )
          : AuthType.password,
      bearerToken: map['bearerToken'],
      baseUrl: map['baseUrl'],
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
        useSSL,
        authType,
        bearerToken,
        baseUrl,
      ];
}
