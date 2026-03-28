class MoveEventRecord {
  final int? id;
  final String recordKey;
  final String moveType;
  final double? confidence;
  final int occurredAtMs;
  final bool synced;

  const MoveEventRecord({
    this.id,
    required this.recordKey,
    required this.moveType,
    this.confidence,
    required this.occurredAtMs,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'record_key': recordKey,
        'move_type': moveType,
        'confidence': confidence,
        'occurred_at_ms': occurredAtMs,
        'synced': synced ? 1 : 0,
      };

  factory MoveEventRecord.fromMap(Map<String, dynamic> map) => MoveEventRecord(
        id: map['id'] as int?,
        recordKey: map['record_key'] as String,
        moveType: map['move_type'] as String,
        confidence: (map['confidence'] as num?)?.toDouble(),
        occurredAtMs: map['occurred_at_ms'] as int,
        synced: (map['synced'] as int) == 1,
      );
}
