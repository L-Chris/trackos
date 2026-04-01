import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/background_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _intervalOptions = [5, 10, 30, 60, 300];
  static const _intervalLabels = ['5 秒', '10 秒', '30 秒', '1 分钟', '5 分钟'];
  static const _usageIntervalOptions = [60, 300, 900, 1800];
  static const _usageIntervalLabels = ['1 分钟', '5 分钟', '15 分钟', '30 分钟'];
  static const _autoSyncIntervalOptions = [300, 600, 1800, 3600];
  static const _autoSyncIntervalLabels = ['5 分钟', '10 分钟', '30 分钟', '1 小时'];

  int _intervalSeconds = 30;
  int _usageIntervalSeconds = 300;
  int _autoSyncIntervalSeconds = 600;
  bool _usageEventsEnabled = true;
  final _serverUrlController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _intervalSeconds = prefs.getInt(kPrefIntervalKey) ?? 30;
      _usageIntervalSeconds = prefs.getInt(kPrefUsageIntervalKey) ?? 300;
      _autoSyncIntervalSeconds = prefs.getInt(kPrefAutoSyncIntervalKey) ?? 600;
      _usageEventsEnabled = prefs.getBool(kPrefUsageEventsEnabledKey) ?? true;
      _serverUrlController.text =
          prefs.getString(kPrefServerUrl) ?? 'https://track-api.rethinkos.com';
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefIntervalKey, _intervalSeconds);
    await prefs.setInt(kPrefUsageIntervalKey, _usageIntervalSeconds);
    await prefs.setInt(kPrefAutoSyncIntervalKey, _autoSyncIntervalSeconds);
    await prefs.setBool(kPrefUsageEventsEnabledKey, _usageEventsEnabled);
    await prefs.setString(kPrefServerUrl, _serverUrlController.text.trim());
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存。重启追踪服务后生效。')),
      );
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '追踪间隔',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '当前：${_intervalLabels[_intervalOptions.indexOf(_intervalSeconds)]}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(_intervalOptions.length, (i) {
                                final selected = _intervalOptions[i] == _intervalSeconds;
                                return ChoiceChip(
                                  label: Text(_intervalLabels[i]),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => _intervalSeconds = _intervalOptions[i]);
                                  },
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '应用使用采集间隔',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '当前：${_usageIntervalLabels[_usageIntervalOptions.indexOf(_usageIntervalSeconds)]}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(_usageIntervalOptions.length, (i) {
                                final selected = _usageIntervalOptions[i] == _usageIntervalSeconds;
                                return ChoiceChip(
                                  label: Text(_usageIntervalLabels[i]),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => _usageIntervalSeconds = _usageIntervalOptions[i]);
                                  },
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '自动同步间隔',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '当前：${_autoSyncIntervalLabels[_autoSyncIntervalOptions.indexOf(_autoSyncIntervalSeconds)]}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '后台追踪服务运行时，会按这个频率自动上传到服务器。',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(_autoSyncIntervalOptions.length, (i) {
                                final selected = _autoSyncIntervalOptions[i] == _autoSyncIntervalSeconds;
                                return ChoiceChip(
                                  label: Text(_autoSyncIntervalLabels[i]),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => _autoSyncIntervalSeconds = _autoSyncIntervalOptions[i]);
                                  },
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: SwitchListTile(
                        value: _usageEventsEnabled,
                        onChanged: (value) => setState(() => _usageEventsEnabled = value),
                        title: const Text('采集设备/前台切换事件'),
                        subtitle: const Text('包括前台切换、亮屏/灭屏、锁屏/解锁事件'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '服务器 URL',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '留空则不上传。格式：http://your-server:port',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _serverUrlController,
                              decoration: const InputDecoration(
                                hintText: 'https://track-api.rethinkos.com',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.cloud),
                              ),
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '会向 {url}/api/locations/report/batch 发送批量 POST 请求，\n'
                              '应用使用汇总会额外发送到 {url}/api/app-usage-summaries/report/batch，\n'
                              '事件流会发送到 {url}/api/usage-events/report/batch，\n'
                              '活动状态会发送到 {url}/api/move-events/report/batch，\n'
                              '支付宝支付通知会发送到 {url}/api/payment-notifications/report/batch。',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('保存设置'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
