import 'package:equatable/equatable.dart';

class SchedulerConfig extends Equatable {
  final bool enabled;
  final int intervalMinutes;
  final bool syncOnlyOnWifi;
  final bool syncOnlyWhenCharging;
  final bool isDailySync;
  final int dailySyncHour; // 0-23
  final int dailySyncMinute; // 0-59

  const SchedulerConfig({
    this.enabled = false,
    this.intervalMinutes = 60, // Default 1 hour
    this.syncOnlyOnWifi = true,
    this.syncOnlyWhenCharging = false,
    this.isDailySync = false,
    this.dailySyncHour = 9, // Default 9:00 AM
    this.dailySyncMinute = 0,
  });

  SchedulerConfig copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? syncOnlyOnWifi,
    bool? syncOnlyWhenCharging,
    bool? isDailySync,
    int? dailySyncHour,
    int? dailySyncMinute,
  }) {
    return SchedulerConfig(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      syncOnlyOnWifi: syncOnlyOnWifi ?? this.syncOnlyOnWifi,
      syncOnlyWhenCharging: syncOnlyWhenCharging ?? this.syncOnlyWhenCharging,
      isDailySync: isDailySync ?? this.isDailySync,
      dailySyncHour: dailySyncHour ?? this.dailySyncHour,
      dailySyncMinute: dailySyncMinute ?? this.dailySyncMinute,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'intervalMinutes': intervalMinutes,
      'syncOnlyOnWifi': syncOnlyOnWifi,
      'syncOnlyWhenCharging': syncOnlyWhenCharging,
      'isDailySync': isDailySync,
      'dailySyncHour': dailySyncHour,
      'dailySyncMinute': dailySyncMinute,
    };
  }

  factory SchedulerConfig.fromMap(Map<String, dynamic> map) {
    return SchedulerConfig(
      enabled: map['enabled'] ?? false,
      intervalMinutes: map['intervalMinutes'] ?? 60,
      syncOnlyOnWifi: map['syncOnlyOnWifi'] ?? true,
      syncOnlyWhenCharging: map['syncOnlyWhenCharging'] ?? false,
      isDailySync: map['isDailySync'] ?? false,
      dailySyncHour: map['dailySyncHour'] ?? 9,
      dailySyncMinute: map['dailySyncMinute'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        intervalMinutes,
        syncOnlyOnWifi,
        syncOnlyWhenCharging,
        isDailySync,
        dailySyncHour,
        dailySyncMinute,
      ];
}
