import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_record.dart';
import 'storage_service.dart';

const String kPrefServerUrl = 'server_url';
const String kSyncUserId = '1';
const String kSyncDeviceId = 'android-device';

/// Sync service: uploads unsynced location records to the configured server.
///
/// POST {serverUrl}/api/locations/report
/// Body: {
///   "userId": "1",
///   "deviceId": "android-device",
///   "latitude": 31.2304,
///   "longitude": 121.4737,
///   "recordedAt": "2026-03-25T02:50:00.000Z",
///   "accuracy": 5,
///   "speed": 1.2,
///   "altitude": 12.5
/// }
///
/// Currently inactive (URL defaults to empty). Fill in the server URL via
/// SettingsScreen to enable syncing.
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
    final serverUrl = (prefs.getString(kPrefServerUrl) ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsynced(limit: 100);
    if (records.isEmpty) return 0;

    final syncedIds = <int>[];

    try {
      for (final record in records) {
        final response = await _dio.post(
          '$serverUrl/api/locations/report',
          data: _buildPayload(record),
        );

        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300 &&
            record.id != null) {
          syncedIds.add(record.id!);
        }
      }

      await _storage.markSynced(syncedIds);
      return syncedIds.length;
    } on DioException {
      // Network/server errors are non-fatal; records remain unsynced and retry later
    }

    return 0;
  }

  Map<String, dynamic> _buildPayload(LocationRecord record) {
    return {
      'userId': kSyncUserId,
      'deviceId': kSyncDeviceId,
      'latitude': record.lat,
      'longitude': record.lng,
      'recordedAt': DateTime.fromMillisecondsSinceEpoch(record.timestamp, isUtc: true).toIso8601String(),
      'accuracy': record.accuracy,
      'speed': record.speed,
      'altitude': record.altitude,
    };
  }
}
