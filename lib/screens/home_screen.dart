import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/background_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/usage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _autoStartEnabled = true;
  bool _hasPermission = false;
  bool _hasBackgroundPermission = false;
  bool _hasUsagePermission = false;
  bool _hasActivityPermission = false;
  bool _locationServiceEnabled = true;
  int _totalRecords = 0;
  int _usageSummaryCount = 0;
  int _usageEventCount = 0;
  int _moveEventCount = 0;
  bool _syncing = false;

  StreamSubscription? _locationSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _usageSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeRefresh();
    }
  }

  Future<void> _resumeRefresh() async {
    await _checkPermissions();
    await _ensureTrackingStarted();
    await _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final count = await StorageService().count();
    final usageCount = await StorageService().countUsageSummaries();
    final usageEventCount = await StorageService().countUsageEvents();
    final moveEventCount = await StorageService().countMoveEvents();
    if (mounted) {
      setState(() {
        _totalRecords = count;
        _usageSummaryCount = usageCount;
        _usageEventCount = usageEventCount;
        _moveEventCount = moveEventCount;
      });
    }
  }

  Future<void> _init() async {
    await _checkPermissions();
    final running = await BackgroundServiceManager.isRunning();
    final count = await StorageService().count();
    final usageCount = await StorageService().countUsageSummaries();
    final usageEventCount = await StorageService().countUsageEvents();
    final moveEventCount = await StorageService().countMoveEvents();
    setState(() {
      _serviceRunning = running;
      _totalRecords = count;
      _usageSummaryCount = usageCount;
      _usageEventCount = usageEventCount;
      _moveEventCount = moveEventCount;
    });
    await _ensureTrackingStarted();
    _subscribeToService();
  }

  Future<void> _checkPermissions() async {
    final locationService = LocationService();
    final hasPerm = await locationService.requestPermissions();
    final hasBg = await locationService.hasBackgroundPermission();
    final serviceOn = await locationService.isLocationServiceEnabled();
    final hasUsage = await UsageService().hasUsageStatsPermission();
    final activityStatus = await Permission.activityRecognition.status;
    if (activityStatus.isDenied) {
      await Permission.activityRecognition.request();
    }
    final hasActivity = await Permission.activityRecognition.isGranted;
    setState(() {
      _hasPermission = hasPerm;
      _hasBackgroundPermission = hasBg;
      _locationServiceEnabled = serviceOn;
      _hasUsagePermission = hasUsage;
      _hasActivityPermission = hasActivity;
    });
  }

  Future<void> _ensureTrackingStarted() async {
    final running = await BackgroundServiceManager.isRunning();
    final canStart = _hasPermission && _hasBackgroundPermission && _locationServiceEnabled;

    if (mounted) {
      setState(() => _serviceRunning = running);
    }

    if (!_autoStartEnabled || !canStart || running) {
      return;
    }

    await BackgroundServiceManager.start();
    if (mounted) {
      setState(() => _serviceRunning = true);
    }
  }

  Future<void> _toggleService() async {
    if (_serviceRunning) {
      await BackgroundServiceManager.stop();
      if (mounted) {
        setState(() {
          _serviceRunning = false;
          _autoStartEnabled = false;
        });
      }
      return;
    }

    final canStart = _hasPermission && _hasBackgroundPermission && _locationServiceEnabled;
    if (!canStart) {
      _showBackgroundPermissionDialog();
      return;
    }

    await BackgroundServiceManager.start();
    if (mounted) {
      setState(() {
        _serviceRunning = true;
        _autoStartEnabled = true;
      });
    }
  }

  void _subscribeToService() {
    _locationSub = BackgroundServiceManager.locationStream.listen((_) async {
      final count = await StorageService().count();
      if (mounted) {
        setState(() {
          _totalRecords = count;
        });
      }
    });

    _usageSub = BackgroundServiceManager.usageStream.listen((data) async {
      if (data == null) return;
      final usageCount = await StorageService().countUsageSummaries();
      final usageEventCount = await StorageService().countUsageEvents();
      if (mounted) {
        setState(() {
          _usageSummaryCount = usageCount;
          _usageEventCount = usageEventCount;
        });
      }
    });

    _statusSub = BackgroundServiceManager.statusStream.listen((data) {
      if (data == null) return;
      if (mounted) {
        setState(() {
          _serviceRunning = data['running'] as bool? ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _statusSub?.cancel();
    _usageSub?.cancel();
    super.dispose();
  }

  void _showBackgroundPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要后台位置权限'),
        content: const Text(
          '后台持续追踪需要"始终允许"位置权限。\n\n'
          '请在系统设置 → 应用 → TrackOS → 权限 → 位置 → 选择"始终允许"。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final result = await SyncService().syncAllPending();
    final usageCount = await StorageService().countUsageSummaries();
    final usageEventCount = await StorageService().countUsageEvents();
    final moveEventCount = await StorageService().countMoveEvents();
    if (mounted) {
      setState(() {
        _syncing = false;
        _usageSummaryCount = usageCount;
        _usageEventCount = usageEventCount;
        _moveEventCount = moveEventCount;
      });
    }

    if (result.locations == -1 || result.usageSummaries == -1 || result.usageEvents == -1) {
      _showSnack('未配置服务器 URL，请在"设置"中填写');
    } else if (result.hasError) {
      _showSnack('同步失败：${result.error}');
    } else {
      _showSnack(
        '已同步定位 ${result.locations} 条，'
        '应用使用 ${result.usageSummaries} 条，'
        '事件 ${result.usageEvents} 条，'
        '活动 ${result.moveEvents} 条',
      );
    }
  }

  Future<void> _openUsageAccessSettings() async {
    await UsageService().openUsageAccessSettings();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrackOS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PermissionCard(
                      hasPermission: _hasPermission,
                      hasBackground: _hasBackgroundPermission,
                      locationServiceEnabled: _locationServiceEnabled,
                      hasUsagePermission: _hasUsagePermission,
                      hasActivityPermission: _hasActivityPermission,
                      usageSummaryCount: _usageSummaryCount,
                      usageEventCount: _usageEventCount,
                      moveEventCount: _moveEventCount,
                      onOpenSettings: _openUsageAccessSettings,
                      onRefresh: _resumeRefresh,
                      onOpenLocationSettings: _showBackgroundPermissionDialog,
                    ),
                    const SizedBox(height: 16),
                    _CollectionOverviewCard(
                      totalRecords: _totalRecords,
                      usageSummaryCount: _usageSummaryCount,
                      usageEventCount: _usageEventCount,
                      moveEventCount: _moveEventCount,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _toggleService,
              icon: Icon(_serviceRunning ? Icons.pause_circle : Icons.play_circle),
              label: Text(_serviceRunning ? '停止追踪' : '开始追踪'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('立即同步到服务器'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.hasPermission,
    required this.hasBackground,
    required this.locationServiceEnabled,
    required this.hasUsagePermission,
    required this.hasActivityPermission,
    required this.usageSummaryCount,
    required this.usageEventCount,
    required this.moveEventCount,
    required this.onOpenSettings,
    required this.onRefresh,
    required this.onOpenLocationSettings,
  });
  final bool hasPermission;
  final bool hasBackground;
  final bool locationServiceEnabled;
  final bool hasUsagePermission;
  final bool hasActivityPermission;
  final int usageSummaryCount;
  final int usageEventCount;
  final int moveEventCount;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, size: 18),
                const SizedBox(width: 8),
                const Text('权限与自动追踪', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => onRefresh(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const Text(
              '应用打开后会自动尝试开启后台追踪；如果权限不足，需要先完成授权。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _PermissionRow(
              label: '系统位置服务（GPS 开关）',
              granted: locationServiceEnabled,
            ),
            _PermissionRow(
              label: '位置权限（前台）',
              granted: hasPermission,
            ),
            _PermissionRow(
              label: '位置权限（始终允许，后台必须）',
              granted: hasBackground,
            ),
            if (!hasPermission || !hasBackground || !locationServiceEnabled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onOpenLocationSettings,
                  icon: const Icon(Icons.my_location),
                  label: const Text('去完善位置权限'),
                ),
              ),
            ],
            const Divider(height: 16),
            _PermissionRow(
              label: '应用使用情况访问（Usage Access）',
              granted: hasUsagePermission,
            ),
            const SizedBox(height: 4),
            Text(
              '本地已采集 $usageSummaryCount 条应用使用汇总记录，$usageEventCount 条事件',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开使用情况访问设置'),
              ),
            ),
            const Divider(height: 16),
            _PermissionRow(
              label: '活动识别权限（步频/运动检测）',
              granted: hasActivityPermission,
            ),
            const SizedBox(height: 4),
            Text(
              '本地已采集 $moveEventCount 条活动状态记录',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: granted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _CollectionOverviewCard extends StatelessWidget {
  const _CollectionOverviewCard({
    required this.totalRecords,
    required this.usageSummaryCount,
    required this.usageEventCount,
    required this.moveEventCount,
  });

  final int totalRecords;
  final int usageSummaryCount;
  final int usageEventCount;
  final int moveEventCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('本地采集概览', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            _InfoRow('定位记录', '$totalRecords 条'),
            _InfoRow('应用使用汇总', '$usageSummaryCount 条'),
            _InfoRow('设备/前台事件', '$usageEventCount 条'),
            _InfoRow('活动状态', '$moveEventCount 条'),
          ],
        ),
      ),
    );
  }
}


class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
