import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/background_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _hasPermission = false;
  bool _hasBackgroundPermission = false;
  bool _locationServiceEnabled = true;
  Map<String, dynamic>? _latestLocation;
  int _totalRecords = 0;
  bool _syncing = false;

  StreamSubscription? _locationSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when the user returns from system Settings
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _init() async {
    await _checkPermissions();
    final running = await BackgroundServiceManager.isRunning();
    final count = await StorageService().count();
    setState(() {
      _serviceRunning = running;
      _totalRecords = count;
    });
    _subscribeToService();
  }

  Future<void> _checkPermissions() async {
    final locationService = LocationService();
    final hasPerm = await locationService.requestPermissions();
    final hasBg = await locationService.hasBackgroundPermission();
    final serviceOn = await locationService.isLocationServiceEnabled();
    setState(() {
      _hasPermission = hasPerm;
      _hasBackgroundPermission = hasBg;
      _locationServiceEnabled = serviceOn;
    });
  }

  void _subscribeToService() {
    _locationSub = BackgroundServiceManager.locationStream.listen((data) async {
      if (data == null) return;
      final count = await StorageService().count();
      if (mounted) {
        setState(() {
          _latestLocation = data;
          _totalRecords = count;
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
    super.dispose();
  }

  Future<void> _toggleService() async {
    if (_serviceRunning) {
      await BackgroundServiceManager.stop();
      setState(() => _serviceRunning = false);
    } else {
      if (!_hasPermission) {
        await _checkPermissions();
        if (!_hasPermission) {
          _showSnack('请先授权位置权限');
          return;
        }
      }
      if (!_hasBackgroundPermission) {
        _showBackgroundPermissionDialog();
        return;
      }
      await BackgroundServiceManager.start();
      setState(() => _serviceRunning = true);
    }
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
    final result = await SyncService().syncPending();
    setState(() => _syncing = false);
    if (result == -1) {
      _showSnack('未配置服务器 URL，请在"设置"中填写');
    } else {
      _showSnack('已同步 $result 条记录');
    }
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
            _StatusCard(running: _serviceRunning),
            const SizedBox(height: 16),
            _PermissionCard(
              hasPermission: _hasPermission,
              hasBackground: _hasBackgroundPermission,
              locationServiceEnabled: _locationServiceEnabled,
              onRefresh: _checkPermissions,
            ),
            const SizedBox(height: 16),
            _LocationCard(data: _latestLocation, totalRecords: _totalRecords),
            const Spacer(),
            FilledButton.icon(
              onPressed: _toggleService,
              icon: Icon(_serviceRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_serviceRunning ? '停止追踪' : '开始追踪'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _serviceRunning ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: running ? Colors.green.shade50 : Colors.grey.shade100,
      child: ListTile(
        leading: Icon(
          running ? Icons.location_on : Icons.location_off,
          color: running ? Colors.green : Colors.grey,
          size: 36,
        ),
        title: Text(
          running ? '追踪进行中' : '追踪已停止',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: running ? Colors.green.shade800 : Colors.grey.shade700,
          ),
        ),
        subtitle: Text(running ? '后台前台服务运行中，持续采集坐标' : '点击下方按钮开始追踪'),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.hasPermission,
    required this.hasBackground,
    required this.locationServiceEnabled,
    required this.onRefresh,
  });
  final bool hasPermission;
  final bool hasBackground;
  final bool locationServiceEnabled;
  final VoidCallback onRefresh;

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
                const Text('权限状态', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
              ],
            ),
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

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.data, required this.totalRecords});
  final Map<String, dynamic>? data;
  final int totalRecords;

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
                const Icon(Icons.gps_fixed, size: 18),
                const SizedBox(width: 8),
                const Text('最新坐标', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '共 $totalRecords 条',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const Divider(),
            if (data == null)
              const Text('暂无数据', style: TextStyle(color: Colors.grey))
            else ...[
              _InfoRow('纬度', '${(data!['lat'] as num).toDouble().toStringAsFixed(6)}°'),
              _InfoRow('经度', '${(data!['lng'] as num).toDouble().toStringAsFixed(6)}°'),
              _InfoRow('精度', '${(data!['accuracy'] as num).toDouble().toStringAsFixed(1)} m'),
              _InfoRow('海拔', '${(data!['altitude'] as num).toDouble().toStringAsFixed(1)} m'),
              _InfoRow('速度', '${(data!['speed'] as num).toDouble().toStringAsFixed(2)} m/s'),
              _InfoRow(
                '时间',
                DateTime.fromMillisecondsSinceEpoch(data!['timestamp'] as int)
                    .toLocal()
                    .toString()
                    .substring(0, 19),
              ),
            ],
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
