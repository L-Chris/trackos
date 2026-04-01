import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Android-specific: force Android's built-in LocationManager (not GMS)
  // This ensures the app works in regions without Google Play Services (e.g., mainland China)
  static final _androidSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    forceLocationManager: true,
  );

  /// Returns current position, or null if unable to obtain.
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _androidSettings,
      );
    } catch (_) {
      return null;
    }
  }

  /// Check and request necessary location permissions.
  /// Returns true when [LocationPermission.always] or
  /// [LocationPermission.whileInUse] is granted.
  /// NOTE: does NOT check whether the system location service (GPS) is on;
  /// use [isLocationServiceEnabled] for that separately.
  Future<bool> requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Check whether the system location service (GPS toggle) is enabled.
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Open the system location settings page (GPS / master location switch).
  Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }

  /// Check whether background location permission is granted (Android 10+).
  Future<bool> hasBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  /// 返回持续位置流（使用内置 LocationManager，无需 Google Play Services）
  ///
  /// [intervalMs] 控制 OS 推送更新的最小间隔，保持 GPS 锁定热备同时节省电量。
  /// 调用方负责取消订阅。
  Stream<Position> getPositionStream({int intervalMs = 5000}) {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      forceLocationManager: true,
      intervalDuration: Duration(milliseconds: intervalMs),
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
