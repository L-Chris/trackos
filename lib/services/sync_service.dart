import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

const String kPrefServerUrl = 'server_url';

/// Sync service: uploads unsynced location records to the configured server.
///
/// POST {serverUrl}/api/locations
/// Body: { "deviceId": "device-id", "records": [ { lat, lng, accuracy, altitude, speed, timestamp }, ... ] }
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
    final serverUrl = (prefs.getString(kPrefServerUrl) ?? '').trim();
    if (serverUrl.isEmpty) return -1;

    final records = await _storage.queryUnsynced(limit: 100);
    if (records.isEmpty) return 0;

    try {
      final payload = {
        'deviceId': 'android-device',
        'records': records.map((r) => r.toJson()).toList(),
      };

      final response = await _dio.post('$serverUrl/api/locations', data: payload);
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final ids = records.map((r) => r.id!).toList();
        await _storage.markSynced(ids);
        return ids.length;
      }
    } on DioException {
      // Network/server errors are non-fatal; records remain unsynced and retry later
    }

    return 0;
  }
}
