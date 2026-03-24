import 'package:flutter/material.dart';
import '../models/location_record.dart';
import '../services/storage_service.dart';

class DataViewerScreen extends StatefulWidget {
  const DataViewerScreen({super.key});

  @override
  State<DataViewerScreen> createState() => _DataViewerScreenState();
}

class _DataViewerScreenState extends State<DataViewerScreen> {
  static const int _pageSize = 50;

  final _storage = StorageService();
  List<LocationRecord> _records = [];
  int _totalCount = 0;
  int _offset = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) _offset = 0;

    final count = await _storage.count();
    final records = await _storage.queryAll(limit: _pageSize, offset: _offset);

    setState(() {
      _totalCount = count;
      if (reset) {
        _records = records;
      } else {
        _records.addAll(records);
      }
      _offset += records.length;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有记录'),
        content: const Text('此操作不可撤销，所有本地坐标记录将被永久删除。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _storage.clearAll();
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('历史数据 ($_totalCount 条)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(reset: true),
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _totalCount > 0 ? _clearAll : null,
            tooltip: '清空',
          ),
        ],
      ),
      body: _records.isEmpty && !_loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无记录', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _records.length + (_offset < _totalCount ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _records.length) {
                  // Load more trigger
                  _load();
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _RecordTile(record: _records[index], index: index);
              },
            ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.index});
  final LocationRecord record;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(record.timestamp).toLocal();
    final timeStr = '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
        '${_p(dt.hour)}:${_p(dt.minute)}:${_p(dt.second)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor:
                  record.synced ? Colors.blue.shade100 : Colors.orange.shade100,
              child: Icon(
                record.synced ? Icons.cloud_done : Icons.cloud_off,
                size: 14,
                color: record.synced ? Colors.blue : Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${record.lat.toStringAsFixed(6)}, ${record.lng.toStringAsFixed(6)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '精度 ${record.accuracy.toStringAsFixed(1)}m  '
                    '海拔 ${record.altitude.toStringAsFixed(1)}m  '
                    '速度 ${record.speed.toStringAsFixed(2)}m/s',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}
