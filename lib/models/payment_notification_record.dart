class PaymentNotificationRecord {
  final String recordKey;
  final String packageName;
  final String notificationKey;
  final int postedAtMs;
  final int receivedAtMs;
  final String title;
  final String text;
  final String? bigText;
  final String? tickerText;
  final String? sourceMetadata;

  const PaymentNotificationRecord({
    required this.recordKey,
    required this.packageName,
    required this.notificationKey,
    required this.postedAtMs,
    required this.receivedAtMs,
    required this.title,
    required this.text,
    this.bigText,
    this.tickerText,
    this.sourceMetadata,
  });

  static PaymentNotificationRecord fromChannelMap(Map<Object?, Object?> map) {
    return PaymentNotificationRecord(
      recordKey: map['recordKey'] as String,
      packageName: map['packageName'] as String,
      notificationKey: map['notificationKey'] as String,
      postedAtMs: (map['postedAtMs'] as num).toInt(),
      receivedAtMs: (map['receivedAtMs'] as num).toInt(),
      title: map['title'] as String,
      text: map['text'] as String,
      bigText: map['bigText'] as String?,
      tickerText: map['tickerText'] as String?,
      sourceMetadata: map['sourceMetadata'] as String?,
    );
  }
}
