class AppUsageSummaryRecord {
  final int? id;
  final String packageName;
  final String appName;
  final int windowStartMs;
  final int windowEndMs;
  final int foregroundTimeMs;
  final int? lastUsedMs;
  final bool synced;

  const AppUsageSummaryRecord({
    this.id,
    required this.packageName,
    required this.appName,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.foregroundTimeMs,
    this.lastUsedMs,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'package_name': packageName,
        'app_name': appName,
        'window_start_ms': windowStartMs,
        'window_end_ms': windowEndMs,
        'foreground_time_ms': foregroundTimeMs,
        'last_used_ms': lastUsedMs,
        'synced': synced ? 1 : 0,
      };

  factory AppUsageSummaryRecord.fromMap(Map<String, dynamic> map) => AppUsageSummaryRecord(
        id: map['id'] as int?,
        packageName: map['package_name'] as String,
        appName: map['app_name'] as String,
        windowStartMs: map['window_start_ms'] as int,
        windowEndMs: map['window_end_ms'] as int,
        foregroundTimeMs: map['foreground_time_ms'] as int,
        lastUsedMs: map['last_used_ms'] as int?,
        synced: (map['synced'] as int) == 1,
      );

  factory AppUsageSummaryRecord.fromChannelMap(Map<Object?, Object?> map) =>
      AppUsageSummaryRecord(
        packageName: (map['packageName'] ?? '') as String,
        appName: (map['appName'] ?? map['packageName'] ?? '') as String,
        windowStartMs: (map['windowStartMs'] as num).toInt(),
        windowEndMs: (map['windowEndMs'] as num).toInt(),
        foregroundTimeMs: (map['foregroundTimeMs'] as num).toInt(),
        lastUsedMs: (map['lastUsedMs'] as num?)?.toInt(),
      );

  String get recordKey => '$packageName:$windowStartMs:$windowEndMs';
}