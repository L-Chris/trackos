import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Android-specific: force Android's built-in LocationManager (not GMS)
  static final _androidSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    forceLocationManager: true,
  );

  // 服务状态流
  final Stream<ServiceStatus> serviceStatusStream = Geolocator.getServiceStatusStream();

  /// 返回当前位置，或 null 如果无法获取
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: _androidSettings);
    } catch (_) {
      return null;
    }
  }

  /// 检查并请求必要的位置权限
  /// 返回 true 当 [LocationPermission.always] 或 [LocationPermission.whileInUse] 已授予
  /// 注意：不检查系统位置服务（GPS）是否开启；使用 [isLocationServiceEnabled] 单独检查
  Future<bool> requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    // 如果权限被拒绝，请求权限
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    
    // 如果权限被永久拒绝，返回 false
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    
    return true;
  }

  /// 检查系统位置服务（GPS 开关）是否启用
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// 打开系统位置设置页面（GPS / 主位置开关）
  Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }

  /// 检查后台位置权限是否已授予（Android 10+）
  Future<bool> hasBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  /// 返回持续位置流（使用内置 LocationManager，无需 Google Play Services）
  /// [intervalMs] 控制 OS 推送更新的最小间隔，保持 GPS 锁定热备同时节省电量
  /// 调用方负责取消订阅
  Stream<Position> getPositionStream({int intervalMs = 5000}) {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      forceLocationManager: true,
      intervalDuration: Duration(milliseconds: intervalMs),
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
