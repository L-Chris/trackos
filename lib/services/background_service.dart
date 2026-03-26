import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'usage_service.dart';
import 'storage_service.dart';
import '../models/location_record.dart';
import '../models/usage_event_record.dart';

// Keys used for IPC events between service isolate and UI
const String kEventLocation = 'location';
const String kEventStatus = 'status';
const String kEventUsage = 'usage';
const String kActionStop = 'stopService';
const String kPrefIntervalKey = 'tracking_interval_seconds';
const String kPrefUsageIntervalKey = 'usage_tracking_interval_seconds';
const String kPrefUsageEventsEnabledKey = 'usage_events_enabled';
const String kPrefLastUsageCollectionKey = 'last_usage_collection_timestamp_ms';
const String kPrefLastUsageEventCollectionKey = 'last_usage_event_collection_timestamp_ms';
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

  // ── Usage collection ──────────────────────────────────────────────────────

  var isCollectingUsage = false;

  /// One collection cycle. Uses [isCollectingUsage] to prevent re-entry.
  Future<void> tryCollectUsage() async {
    if (!Platform.isAndroid || isCollectingUsage) return;
    isCollectingUsage = true;
    try {
      final hasPermission = await usageService.hasUsageStatsPermission();
      if (!hasPermission) {
        debugPrint('[TrackOS] Usage: no permission — skipping');
        return;
      }

      // Reload to pick up any changes written by the main isolate.
      await prefs.reload();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final lastCollectedAt =
          prefs.getInt(kPrefLastUsageCollectionKey) ?? (now - usageIntervalSeconds * 1000);
      if (lastCollectedAt >= now) {
        debugPrint('[TrackOS] Usage: recently collected, skipping');
        return;
      }

      debugPrint('[TrackOS] Usage: querying window [$lastCollectedAt, $now]');
      final summaries = await usageService.queryUsageSummaries(
        startMs: lastCollectedAt,
        endMs: now,
      );
      final usageEventsEnabled = prefs.getBool(kPrefUsageEventsEnabledKey) ?? true;
      final lastEventCollectedAt = prefs.getInt(kPrefLastUsageEventCollectionKey) ?? lastCollectedAt;
      final List<UsageEventRecord> events = usageEventsEnabled
          ? await usageService.queryUsageEvents(
              startMs: lastEventCollectedAt,
              endMs: now,
            )
          : <UsageEventRecord>[];
      debugPrint('[TrackOS] Usage: ${summaries.length} records returned');
      debugPrint('[TrackOS] Usage events: ${events.length} records returned');

      if (summaries.isNotEmpty) {
        await storage.insertUsageSummaries(summaries);
      }
      if (events.isNotEmpty) {
        await storage.insertUsageEvents(events);
      }
      service.invoke(kEventUsage, {
        'summaryCount': summaries.length,
        'eventCount': events.length,
      });
      await prefs.setInt(kPrefLastUsageCollectionKey, now);
      if (usageEventsEnabled) {
        await prefs.setInt(kPrefLastUsageEventCollectionKey, now);
      }
    } catch (e, st) {
      // Log rather than silently swallow so issues are visible in adb logcat.
      debugPrint('[TrackOS] Usage collection error: $e\n$st');
    } finally {
      isCollectingUsage = false;
    }
  }

  // Run once immediately (don't make the user wait a full interval).
  tryCollectUsage();
  // Then repeat on the configured interval.
  Timer.periodic(Duration(seconds: usageIntervalSeconds), (_) => tryCollectUsage());

  // ── Location tracking ─────────────────────────────────────────────────────

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

      // Push real-time update to UI if it is in foreground.
      service.invoke(kEventLocation, {
        'lat': record.lat,
        'lng': record.lng,
        'accuracy': record.accuracy,
        'altitude': record.altitude,
        'speed': record.speed,
        'timestamp': record.timestamp,
      });
    } catch (e) {
      debugPrint('[TrackOS] Location error: $e');
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

  /// Listen for usage-stats collection events from the background service.
  static Stream<Map<String, dynamic>?> get usageStream =>
      _service.on(kEventUsage);
}
