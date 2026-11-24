import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/db.dart';
import '../core/map_settings.dart';
import 'map_settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _localId;
  Map<String, num>? _totals;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = await AppDb.localId();
    final totals = await AppDb.totals();
    if (!mounted) return;
    setState(() {
      _localId = id;
      _totals = totals;
    });
  }

  String _mask(String id) =>
      id.length <= 12 ? id : '${id.substring(0, 8)}••••••${id.substring(id.length - 4)}';

  String _sourceLabel() {
    final s = context.watch<MapSettings>();
    if (s.offlineMode) {
      return '离线包 ${s.activeOffline!.name}';
    }
    final name = s.source.name;
    return s.usingCustomTemplate ? '$name（自定义镜像）' : name;
  }

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final totalKm = t != null ? (t['distance']! / 1000).toStringAsFixed(2) : '-';
    final totalH = t != null ? (t['duration']! / 3600).toStringAsFixed(1) : '-';
    final count = t?['count']?.toString() ?? '-';
    final days = t?['days']?.toString() ?? '-';

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('累计足迹', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat(totalKm, '总里程 km'),
                _stat(totalH, '总时长 h'),
                _stat(count, '记录次数'),
                _stat(days, '记录天数'),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
          child: ListTile(
            title: const Text('本地账号 ID', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(_localId == null ? '生成中…' : _mask(_localId!)),
            trailing: const Icon(Icons.copy, size: 18),
            onTap: _localId == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _localId!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('完整 ID 已复制到剪贴板')));
                    }
                  },
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
          child: ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('底图与离线地图', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('当前：${_sourceLabel()}',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MapSettingsPage())),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.lock_outline, size: 18),
                SizedBox(width: 8),
                Text('隐私说明', style: TextStyle(fontWeight: FontWeight.w500)),
              ]),
              SizedBox(height: 10),
              Text(
                '本应用为完全本地化应用：\n\n'
                '· 打开即自动生成本地账号，无需注册登录\n'
                '· 所有轨迹、统计数据仅存储在设备本地数据库中\n'
                '· 不上传任何数据，没有云端备份与好友共享\n'
                '· 地图底图仅用于显示，不含你的任何个人信息\n\n'
                '卸载应用或清除应用数据将永久删除全部足迹。',
                style: TextStyle(fontSize: 13, height: 1.7),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}
