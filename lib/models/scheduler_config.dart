import 'package:equatable/equatable.dart';

enum SyncScheduleType { interval, daily, weekly }

class SchedulerConfig extends Equatable {
  final bool enabled;
  final SyncScheduleType scheduleType;
  final int intervalMinutes;
  final bool syncOnlyOnWifi;
  final bool syncOnlyWhenCharging;
  
  // Daily/Weekly sync time settings
  final int syncHour; // 0-23
  final int syncMinute; // 0-59
  
  // Weekly sync settings
  final int weekDay; // 1-7 (Monday = 1, Sunday = 7)

  const SchedulerConfig({
    this.enabled = false,
    this.scheduleType = SyncScheduleType.interval,
    this.intervalMinutes = 60, // Default 1 hour
    this.syncOnlyOnWifi = true,
    this.syncOnlyWhenCharging = false,
    this.syncHour = 9, // Default 9:00 AM
    this.syncMinute = 0,
    this.weekDay = 1, // Default Monday
  });

  // Legacy support - keep for backward compatibility
  bool get isDailySync => scheduleType == SyncScheduleType.daily;
  int get dailySyncHour => syncHour;
  int get dailySyncMinute => syncMinute;

  SchedulerConfig copyWith({
    bool? enabled,
    SyncScheduleType? scheduleType,
    int? intervalMinutes,
    bool? syncOnlyOnWifi,
    bool? syncOnlyWhenCharging,
    int? syncHour,
    int? syncMinute,
    int? weekDay,
    // Legacy support
    bool? isDailySync,
    int? dailySyncHour,
    int? dailySyncMinute,
  }) {
    return SchedulerConfig(
      enabled: enabled ?? this.enabled,
      scheduleType: scheduleType ?? 
          (isDailySync == true ? SyncScheduleType.daily : this.scheduleType),
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      syncOnlyOnWifi: syncOnlyOnWifi ?? this.syncOnlyOnWifi,
      syncOnlyWhenCharging: syncOnlyWhenCharging ?? this.syncOnlyWhenCharging,
      syncHour: syncHour ?? dailySyncHour ?? this.syncHour,
      syncMinute: syncMinute ?? dailySyncMinute ?? this.syncMinute,
      weekDay: weekDay ?? this.weekDay,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'scheduleType': scheduleType.name,
      'intervalMinutes': intervalMinutes,
      'syncOnlyOnWifi': syncOnlyOnWifi,
      'syncOnlyWhenCharging': syncOnlyWhenCharging,
      'syncHour': syncHour,
      'syncMinute': syncMinute,
      'weekDay': weekDay,
      // Legacy support
      'isDailySync': isDailySync,
      'dailySyncHour': dailySyncHour,
      'dailySyncMinute': dailySyncMinute,
    };
  }

  factory SchedulerConfig.fromMap(Map<String, dynamic> map) {
    // Handle legacy data
    final scheduleTypeStr = map['scheduleType'] as String?;
    final scheduleType = scheduleTypeStr != null
        ? SyncScheduleType.values.firstWhere(
            (e) => e.name == scheduleTypeStr,
            orElse: () => map['isDailySync'] == true 
                ? SyncScheduleType.daily 
                : SyncScheduleType.interval,
          )
        : map['isDailySync'] == true 
            ? SyncScheduleType.daily 
            : SyncScheduleType.interval;
    
    return SchedulerConfig(
      enabled: map['enabled'] ?? false,
      scheduleType: scheduleType,
      intervalMinutes: map['intervalMinutes'] ?? 60,
      syncOnlyOnWifi: map['syncOnlyOnWifi'] ?? true,
      syncOnlyWhenCharging: map['syncOnlyWhenCharging'] ?? false,
      syncHour: map['syncHour'] ?? map['dailySyncHour'] ?? 9,
      syncMinute: map['syncMinute'] ?? map['dailySyncMinute'] ?? 0,
      weekDay: map['weekDay'] ?? 1,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        scheduleType,
        intervalMinutes,
        syncOnlyOnWifi,
        syncOnlyWhenCharging,
        syncHour,
        syncMinute,
        weekDay,
      ];
}
