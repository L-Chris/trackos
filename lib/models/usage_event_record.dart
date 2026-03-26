class UsageEventRecord {
  final int? id;
  final String recordKey;
  final String eventType;
  final String? packageName;
  final String? className;
  final int occurredAtMs;
  final String source;
  final String? metadata;
  final bool synced;

  const UsageEventRecord({
    this.id,
    required this.recordKey,
    required this.eventType,
    this.packageName,
    this.className,
    required this.occurredAtMs,
    required this.source,
    this.metadata,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'record_key': recordKey,
        'event_type': eventType,
        'package_name': packageName,
        'class_name': className,
        'occurred_at_ms': occurredAtMs,
        'source': source,
        'metadata': metadata,
        'synced': synced ? 1 : 0,
      };

  factory UsageEventRecord.fromMap(Map<String, dynamic> map) => UsageEventRecord(
        id: map['id'] as int?,
        recordKey: map['record_key'] as String,
        eventType: map['event_type'] as String,
        packageName: map['package_name'] as String?,
        className: map['class_name'] as String?,
        occurredAtMs: map['occurred_at_ms'] as int,
        source: map['source'] as String,
        metadata: map['metadata'] as String?,
        synced: (map['synced'] as int) == 1,
      );

  factory UsageEventRecord.fromChannelMap(Map<Object?, Object?> map) => UsageEventRecord(
        recordKey: (map['recordKey'] ?? '') as String,
        eventType: (map['eventType'] ?? '') as String,
        packageName: map['packageName'] as String?,
        className: map['className'] as String?,
        occurredAtMs: (map['occurredAtMs'] as num).toInt(),
        source: (map['source'] ?? 'android_usage_events') as String,
        metadata: map['metadata'] as String?,
      );
}