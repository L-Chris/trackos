import 'dart:io';

import 'package:flutter/services.dart';

import '../models/payment_notification_record.dart';

class PaymentNotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.rethinkos.trackos/payment_notifications');

  Future<bool> hasNotificationAccess() async {
    if (!Platform.isAndroid) return false;
    return (await _channel.invokeMethod<bool>('hasNotificationAccess')) ?? false;
  }

  Future<void> openNotificationAccessSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openNotificationAccessSettings');
  }

  Future<int> countPendingPaymentNotifications() async {
    if (!Platform.isAndroid) return 0;
    return (await _channel.invokeMethod<int>('countPendingPaymentNotifications')) ?? 0;
  }

  Future<List<PaymentNotificationRecord>> queryUnsyncedPaymentNotifications({
    int limit = 200,
  }) async {
    if (!Platform.isAndroid) return const [];
    final result = await _channel.invokeListMethod<dynamic>(
          'queryUnsyncedPaymentNotifications',
          {'limit': limit},
        ) ??
        const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(PaymentNotificationRecord.fromChannelMap)
        .toList();
  }

  Future<void> markPaymentNotificationsSynced(List<String> recordKeys) async {
    if (!Platform.isAndroid || recordKeys.isEmpty) return;
    await _channel.invokeMethod<void>(
      'markPaymentNotificationsSynced',
      {'recordKeys': recordKeys},
    );
  }
}
