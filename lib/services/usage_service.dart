import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_usage_summary_record.dart';
import '../models/usage_event_record.dart';

class UsageService {
  static const MethodChannel _channel = MethodChannel('com.rethinkos.trackos/usage');

  Future<bool> hasUsageStatsPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }

    return (await _channel.invokeMethod<bool>('hasUsageStatsPermission')) ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<List<AppUsageSummaryRecord>> queryUsageSummaries({
    required int startMs,
    required int endMs,
  }) async {
    if (!Platform.isAndroid) {
      return <AppUsageSummaryRecord>[];
    }

    final result = await _channel.invokeListMethod<dynamic>(
          'queryUsageSummaries',
          {
            'startMs': startMs,
            'endMs': endMs,
          },
        ) ??
        const [];

    return result
        .whereType<Map<Object?, Object?>>()
        .map(AppUsageSummaryRecord.fromChannelMap)
        .where((record) => record.packageName.isNotEmpty && record.foregroundTimeMs > 0)
        .toList();
  }

  Future<List<UsageEventRecord>> queryUsageEvents({
    required int startMs,
    required int endMs,
  }) async {
    if (!Platform.isAndroid) {
      return <UsageEventRecord>[];
    }

    final result = await _channel.invokeListMethod<dynamic>(
          'queryUsageEvents',
          {
            'startMs': startMs,
            'endMs': endMs,
          },
        ) ??
        const [];

    return result
        .whereType<Map<Object?, Object?>>()
        .map(UsageEventRecord.fromChannelMap)
        .where((event) => event.recordKey.isNotEmpty && event.eventType.isNotEmpty)
        .toList();
  }
}