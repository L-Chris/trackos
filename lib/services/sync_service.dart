import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_usage_summary_record.dart';
import '../models/location_record.dart';
import 'storage_service.dart';

const String kPrefServerUrl = 'server_url';
const String kSyncUserId = '1';
const String kSyncDeviceId = 'android-device';

class SyncCounts {
  final int locations;
  final int usageSummaries;

  const SyncCounts({
    required this.locations,
    required this.usageSummaries,
  });
}

/// Sync service: uploads unsynced location records to the configured server.
///
/// POST {serverUrl}/api/locations/report/batch
/// Body: {
///   "userId": "1",
///   "deviceId": "android-device",
///   "records": [
///     {
///       "latitude": 31.2304,
///       "longitude": 121.4737,
///       "recordedAt": "2026-03-25T02:50:00.000Z",
///       "accuracy": 5,
///       "speed": 1.2,
///       "altitude": 12.5
///     }
///   ]
/// }
///
/// Currently defaults to http://track-api.rethinkos.com if not configured.
/// Override via SettingsScreen to use a different server.
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

  /// Uploads all unsynced records. Returns the number of successfully synced records,
  /// or -1 if skipped (no URL configured).
  Future<int> syncPending() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = (prefs.getString(kPrefServerUrl) ?? 'http://track-api.rethinkos.com').trim().replaceAll(RegExp(r'/+$'), '');
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsynced(limit: 100);
    if (records.isEmpty) return 0;

    try {
      final response = await _dio.post(
        '$serverUrl/api/locations/report/batch',
        data: _buildBatchPayload(records),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final acceptedCount = _extractAcceptedCount(response.data, records.length);
        final syncedIds = records
            .take(acceptedCount)
            .map((record) => record.id)
            .whereType<int>()
            .toList();

        await _storage.markSynced(syncedIds);
        return syncedIds.length;
      }
    } on DioException {
      // Network/server errors are non-fatal; records remain unsynced and retry later
    }

    return 0;
  }

  Future<int> syncPendingUsageSummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = (prefs.getString(kPrefServerUrl) ?? 'http://track-api.rethinkos.com').trim().replaceAll(RegExp(r'/+$'), '');
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsyncedUsageSummaries(limit: 100);
    if (records.isEmpty) return 0;

    try {
      final response = await _dio.post(
        '$serverUrl/api/app-usage-summaries/report/batch',
        data: _buildUsageSummaryBatchPayload(records),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final acceptedCount = _extractAcceptedCount(response.data, records.length);
        final syncedIds = records
            .take(acceptedCount)
            .map((record) => record.id)
            .whereType<int>()
            .toList();

        await _storage.markUsageSummariesSynced(syncedIds);
        return syncedIds.length;
      }
    } on DioException {
      // Usage summary sync shares the same retry model as location sync.
    }

    return 0;
  }

  Future<SyncCounts> syncAllPending() async {
    final locations = await syncPending();
    final usageSummaries = await syncPendingUsageSummaries();
    return SyncCounts(
      locations: locations,
      usageSummaries: usageSummaries,
    );
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
      'recordedAt': DateTime.fromMillisecondsSinceEpoch(record.timestamp, isUtc: true).toIso8601String(),
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
      'recordKey': '${kSyncDeviceId}:${record.recordKey}',
      'packageName': record.packageName,
      'appName': record.appName,
      'windowStartAt': DateTime.fromMillisecondsSinceEpoch(record.windowStartMs, isUtc: true).toIso8601String(),
      'windowEndAt': DateTime.fromMillisecondsSinceEpoch(record.windowEndMs, isUtc: true).toIso8601String(),
      'foregroundTimeMs': record.foregroundTimeMs,
      'lastUsedAt': record.lastUsedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(record.lastUsedMs!, isUtc: true).toIso8601String(),
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
