import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_usage_summary_record.dart';
import '../models/location_record.dart';
import '../models/move_event_record.dart';
import '../models/payment_notification_record.dart';
import '../models/usage_event_record.dart';
import 'payment_notification_service.dart';
import 'storage_service.dart';

const String kPrefServerUrl = 'server_url';
const String kSyncUserId = '1';
const String kSyncDeviceId = 'android-device';

class SyncCounts {
  final int locations;
  final int usageSummaries;
  final int usageEvents;
  final int moveEvents;
  final int paymentNotifications;
  /// Non-null when a network / server error occurred during sync.
  final String? error;

  const SyncCounts({
    required this.locations,
    required this.usageSummaries,
    required this.usageEvents,
    required this.moveEvents,
    required this.paymentNotifications,
    this.error,
  });

  bool get hasError => error != null;
}

/// Sync service: uploads unsynced records to the configured server.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    contentType: 'application/json',
  ));

  final _storage = StorageService();
  final _paymentNotificationService = PaymentNotificationService();

  Future<String> _resolveServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(kPrefServerUrl) ?? 'https://track-api.rethinkos.com')
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
  }

  /// Uploads unsynced location records. Returns -1 if skipped (no URL configured).
  Future<int> syncPending() async {
    final serverUrl = await _resolveServerUrl();
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsynced(limit: 100);
    if (records.isEmpty) return 0;

    final response = await _dio.post(
      '$serverUrl/api/locations/report/batch',
      data: _buildBatchPayload(records),
    );

    if (_isSuccess(response.statusCode)) {
      final acceptedCount = _extractAcceptedCount(response.data, records.length);
      final syncedIds = records
          .take(acceptedCount)
          .map((record) => record.id)
          .whereType<int>()
          .toList();

      await _storage.markSynced(syncedIds);
      return syncedIds.length;
    }
    return 0;
  }

  Future<int> syncPendingUsageSummaries() async {
    final serverUrl = await _resolveServerUrl();
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsyncedUsageSummaries(limit: 100);
    if (records.isEmpty) return 0;

    final response = await _dio.post(
      '$serverUrl/api/app-usage-summaries/report/batch',
      data: _buildUsageSummaryBatchPayload(records),
    );

    if (_isSuccess(response.statusCode)) {
      final acceptedCount = _extractAcceptedCount(response.data, records.length);
      final syncedIds = records
          .take(acceptedCount)
          .map((record) => record.id)
          .whereType<int>()
          .toList();

      await _storage.markUsageSummariesSynced(syncedIds);
      return syncedIds.length;
    }
    return 0;
  }

  Future<int> syncPendingUsageEvents() async {
    final serverUrl = await _resolveServerUrl();
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsyncedUsageEvents(limit: 200);
    if (records.isEmpty) return 0;

    final response = await _dio.post(
      '$serverUrl/api/usage-events/report/batch',
      data: _buildUsageEventBatchPayload(records),
    );

    if (_isSuccess(response.statusCode)) {
      final acceptedCount = _extractAcceptedCount(response.data, records.length);
      final syncedIds = records
          .take(acceptedCount)
          .map((record) => record.id)
          .whereType<int>()
          .toList();

      await _storage.markUsageEventsSynced(syncedIds);
      return syncedIds.length;
    }
    return 0;
  }

  Future<int> syncPendingMoveEvents() async {
    final serverUrl = await _resolveServerUrl();
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsyncedMoveEvents(limit: 200);
    if (records.isEmpty) return 0;

    final response = await _dio.post(
      '$serverUrl/api/move-events/report/batch',
      data: _buildMoveEventBatchPayload(records),
    );

    if (_isSuccess(response.statusCode)) {
      final acceptedCount = _extractAcceptedCount(response.data, records.length);
      final syncedIds = records
          .take(acceptedCount)
          .map((record) => record.id)
          .whereType<int>()
          .toList();

      await _storage.markMoveEventsSynced(syncedIds);
      return syncedIds.length;
    }
    return 0;
  }

  Future<int> syncPendingPaymentNotifications() async {
    final serverUrl = await _resolveServerUrl();
    if (serverUrl.isEmpty) return -1;

    final records = await _paymentNotificationService.queryUnsyncedPaymentNotifications(
      limit: 200,
    );
    if (records.isEmpty) return 0;

    final response = await _dio.post(
      '$serverUrl/api/payment-notifications/report/batch',
      data: _buildPaymentNotificationBatchPayload(records),
    );

    if (_isSuccess(response.statusCode)) {
      final acceptedCount = _extractAcceptedCount(response.data, records.length);
      final syncedRecordKeys = records
          .take(acceptedCount)
          .map((record) => record.recordKey)
          .toList();

      await _paymentNotificationService.markPaymentNotificationsSynced(syncedRecordKeys);
      return syncedRecordKeys.length;
    }
    return 0;
  }

  Future<SyncCounts> syncAllPending() async {
    int locations = 0;
    int usageSummaries = 0;
    int usageEvents = 0;
    int moveEvents = 0;
    int paymentNotifications = 0;
    String? error;

    try {
      locations = await syncPending();
    } on DioException catch (e) {
      error = _formatDioError(e);
    } catch (e) {
      error = e.toString();
    }

    try {
      usageSummaries = await syncPendingUsageSummaries();
    } on DioException catch (e) {
      error ??= _formatDioError(e);
    } catch (e) {
      error ??= e.toString();
    }

    try {
      usageEvents = await syncPendingUsageEvents();
    } on DioException catch (e) {
      error ??= _formatDioError(e);
    } catch (e) {
      error ??= e.toString();
    }

    try {
      moveEvents = await syncPendingMoveEvents();
    } on DioException catch (e) {
      error ??= _formatDioError(e);
    } catch (e) {
      error ??= e.toString();
    }

    try {
      paymentNotifications = await syncPendingPaymentNotifications();
    } on DioException catch (e) {
      error ??= _formatDioError(e);
    } catch (e) {
      error ??= e.toString();
    }

    return SyncCounts(
      locations: locations,
      usageSummaries: usageSummaries,
      usageEvents: usageEvents,
      moveEvents: moveEvents,
      paymentNotifications: paymentNotifications,
      error: error,
    );
  }

  bool _isSuccess(int? statusCode) =>
      statusCode != null && statusCode >= 200 && statusCode < 300;

  String _formatDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接服务器（${e.message ?? "连接错误"}）';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return '服务器返回错误 HTTP $code';
      default:
        return e.message ?? '未知网络错误';
    }
  }

  Map<String, dynamic> _buildBatchPayload(List<LocationRecord> records) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'records': records.map(_buildRecordPayload).toList(),
    };
  }

  Map<String, dynamic> _buildRecordPayload(LocationRecord record) {
    return {
      'latitude': record.lat,
      'longitude': record.lng,
      'recordedAt': DateTime.fromMillisecondsSinceEpoch(record.timestamp, isUtc: true)
          .toIso8601String(),
      'accuracy': record.accuracy,
      'speed': record.speed,
      'altitude': record.altitude,
    };
  }

  Map<String, dynamic> _buildUsageSummaryBatchPayload(List<AppUsageSummaryRecord> records) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'records': records.map(_buildUsageSummaryPayload).toList(),
    };
  }

  Map<String, dynamic> _buildUsageSummaryPayload(AppUsageSummaryRecord record) {
    return {
      'recordKey': '$kSyncDeviceId:${record.recordKey}',
      'packageName': record.packageName,
      'appName': record.appName,
      'windowStartAt': DateTime.fromMillisecondsSinceEpoch(record.windowStartMs, isUtc: true)
          .toIso8601String(),
      'windowEndAt': DateTime.fromMillisecondsSinceEpoch(record.windowEndMs, isUtc: true)
          .toIso8601String(),
      'foregroundTimeMs': record.foregroundTimeMs,
      'lastUsedAt': record.lastUsedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(record.lastUsedMs!, isUtc: true)
              .toIso8601String(),
    };
  }

  Map<String, dynamic> _buildUsageEventBatchPayload(List<UsageEventRecord> records) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'records': records.map(_buildUsageEventPayload).toList(),
    };
  }

  Map<String, dynamic> _buildUsageEventPayload(UsageEventRecord record) {
    return {
      'recordKey': '$kSyncDeviceId:${record.recordKey}',
      'eventType': record.eventType,
      'packageName': record.packageName,
      'className': record.className,
      'occurredAt': DateTime.fromMillisecondsSinceEpoch(record.occurredAtMs, isUtc: true)
          .toIso8601String(),
      'source': record.source,
      'metadata': record.metadata,
    };
  }

  Map<String, dynamic> _buildMoveEventBatchPayload(List<MoveEventRecord> records) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'records': records.map(_buildMoveEventPayload).toList(),
    };
  }

  Map<String, dynamic> _buildMoveEventPayload(MoveEventRecord record) {
    return {
      'recordKey': '$kSyncDeviceId:${record.recordKey}',
      'moveType': record.moveType,
      'confidence': record.confidence,
      'occurredAt': DateTime.fromMillisecondsSinceEpoch(record.occurredAtMs, isUtc: true)
          .toIso8601String(),
    };
  }

  Map<String, dynamic> _buildPaymentNotificationBatchPayload(
    List<PaymentNotificationRecord> records,
  ) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'records': records.map(_buildPaymentNotificationPayload).toList(),
    };
  }

  Map<String, dynamic> _buildPaymentNotificationPayload(
    PaymentNotificationRecord record,
  ) {
    return {
      'recordKey': record.recordKey,
      'packageName': record.packageName,
      'notificationKey': record.notificationKey,
      'postedAt': DateTime.fromMillisecondsSinceEpoch(record.postedAtMs, isUtc: true)
          .toIso8601String(),
      'receivedAt': DateTime.fromMillisecondsSinceEpoch(record.receivedAtMs, isUtc: true)
          .toIso8601String(),
      'title': record.title,
      'text': record.text,
      'bigText': record.bigText,
      'tickerText': record.tickerText,
      'sourceMetadata': record.sourceMetadata,
    };
  }

  int _extractAcceptedCount(dynamic responseData, int fallback) {
    if (responseData is Map<String, dynamic>) {
      final data = responseData['data'];
      if (data is Map<String, dynamic>) {
        final acceptedCount = data['acceptedCount'];
        if (acceptedCount is int) {
          return acceptedCount;
        }
        if (acceptedCount is num) {
          return acceptedCount.toInt();
        }
      }
    }

    return fallback;
  }
}
