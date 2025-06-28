import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';
import '../models/scheduler_config.dart';

class SettingsService {
  static const String _serverConfigKey = 'server_config';
  static const String _schedulerConfigKey = 'scheduler_config';
  static const String _autoDeleteKey = 'auto_delete_enabled';
  static const String _firstRunKey = 'first_run';

  static Future<ServerConfig?> getServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? configJson = prefs.getString(_serverConfigKey);
    
    if (configJson != null) {
      final Map<String, dynamic> configMap = json.decode(configJson);
      return ServerConfig.fromMap(configMap);
    }
    return null;
  }

  static Future<bool> saveServerConfig(ServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final String configJson = json.encode(config.toMap());
    return await prefs.setString(_serverConfigKey, configJson);
  }

  static Future<SchedulerConfig> getSchedulerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? configJson = prefs.getString(_schedulerConfigKey);
    
    if (configJson != null) {
      final Map<String, dynamic> configMap = json.decode(configJson);
      return SchedulerConfig.fromMap(configMap);
    }
    return const SchedulerConfig(); // Return default config
  }

  static Future<bool> saveSchedulerConfig(SchedulerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final String configJson = json.encode(config.toMap());
    return await prefs.setString(_schedulerConfigKey, configJson);
  }

  static Future<bool> getAutoDeleteEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoDeleteKey) ?? false;
  }

  static Future<bool> setAutoDeleteEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setBool(_autoDeleteKey, enabled);
  }

  static Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstRunKey) ?? true;
  }

  static Future<bool> setFirstRunCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setBool(_firstRunKey, false);
  }

  static Future<bool> clearAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.clear();
  }

  static Future<Map<String, dynamic>> getAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final Set<String> keys = prefs.getKeys();
    final Map<String, dynamic> settings = {};
    
    for (String key in keys) {
      final dynamic value = prefs.get(key);
      settings[key] = value;
    }
    
    return settings;
  }

  static Future<bool> saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setString(key, value);
  }

  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }
}
