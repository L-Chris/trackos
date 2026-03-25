import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'usage_service.dart';
import 'storage_service.dart';
import '../models/location_record.dart';

// Keys used for IPC events between service isolate and UI
const String kEventLocation = 'location';
const String kEventStatus = 'status';
const String kActionStop = 'stopService';
const String kPrefIntervalKey = 'tracking_interval_seconds';
const String kPrefUsageIntervalKey = 'usage_tracking_interval_seconds';
const String kPrefLastUsageCollectionKey = 'last_usage_collection_timestamp_ms';
const String kNotificationChannelId = 'trackos_location';
const int kForegroundNotificationId = 888;

/// Initialize and configure flutter_background_service.
/// Must be called from main() before runApp().
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      isForegroundMode: true,
      autoStart: false,
      notificationChannelId: kNotificationChannelId,
      initialNotificationTitle: 'TrackOS',
      initialNotificationContent: '位置追踪已启动',
      foregroundServiceNotificationId: kForegroundNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
      onBackground: _onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

/// Entry point for the background service isolate.
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  final usageService = UsageService();

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'TrackOS',
      content: '位置追踪运行中',
    );
  }

  // Listen for stop command from UI
  service.on(kActionStop).listen((_) async {
    service.invoke(kEventStatus, {'running': false});
    await service.stopSelf();
  });

  // Read interval from shared prefs (default 30s)
  final prefs = await SharedPreferences.getInstance();
  int intervalSeconds = prefs.getInt(kPrefIntervalKey) ?? 30;
  int usageIntervalSeconds = prefs.getInt(kPrefUsageIntervalKey) ?? 300;

  // Android: force built-in LocationManager (no Google Play Services needed)
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    forceLocationManager: true,
  );

  // Broadcast initial status
  service.invoke(kEventStatus, {'running': true});

  var isCollectingUsage = false;

  // Periodic tracking timer
  Timer.periodic(Duration(seconds: intervalSeconds), (_) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      ).timeout(const Duration(seconds: 15));

      final record = LocationRecord(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        timestamp: position.timestamp.millisecondsSinceEpoch,
      );

      await storage.insert(record);

      // Push real-time update to UI if it is foreground
      service.invoke(kEventLocation, {
        'lat': record.lat,
        'lng': record.lng,
        'accuracy': record.accuracy,
        'altitude': record.altitude,
        'speed': record.speed,
        'timestamp': record.timestamp,
      });
    } catch (_) {
      // Silently ignore individual collection errors
    }
  });

  Timer.periodic(Duration(seconds: usageIntervalSeconds), (_) async {
    if (!Platform.isAndroid || isCollectingUsage) {
      return;
    }

    isCollectingUsage = true;
    try {
      final hasPermission = await usageService.hasUsageStatsPermission();
      if (!hasPermission) {
        return;
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final lastCollectedAt = prefs.getInt(kPrefLastUsageCollectionKey) ?? (now - usageIntervalSeconds * 1000);
      if (lastCollectedAt >= now) {
        return;
      }

      final summaries = await usageService.queryUsageSummaries(
        startMs: lastCollectedAt,
        endMs: now,
      );

      await storage.insertUsageSummaries(summaries);
      await prefs.setInt(kPrefLastUsageCollectionKey, now);
    } catch (_) {
      // Ignore usage collection errors and retry in the next cycle.
    } finally {
      isCollectingUsage = false;
    }
  });
}

class BackgroundServiceManager {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<bool> isRunning() => _service.isRunning();

  static Future<void> start() async {
    await _service.startService();
  }

  static Future<void> stop() async {
    _service.invoke(kActionStop);
  }

  /// Listen for real-time location events from the background service.
  static Stream<Map<String, dynamic>?> get locationStream =>
      _service.on(kEventLocation);

  /// Listen for service status events.
  static Stream<Map<String, dynamic>?> get statusStream =>
      _service.on(kEventStatus);
}
