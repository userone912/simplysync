import 'dart:developer' as developer;

class Logger {
  static const String _appName = 'SimplySync';

  static void debug(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? _appName,
      level: 500, // Debug level
    );
  }

  static void info(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? _appName,
      level: 800, // Info level
    );
  }

  static void warning(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? _appName,
      level: 900, // Warning level
    );
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: tag ?? _appName,
      level: 1000, // Error level
      error: error,
      stackTrace: stackTrace,
    );
  }
}
