import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_nav.dart';
import '../core/db.dart';
import '../core/map_settings.dart';
import '../core/tracker.dart';
import 'about_page.dart';
import 'data_backup_page.dart';
import 'map_settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _localId;
  Map<String, num>? _totals;

  /// 上次触发刷新的数据标记（标签页 + 记录版本号）
  String? _stamp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 切回本页或新增记录时刷新统计数据
  void _maybeReload() {
    final navIndex = context.select<AppNav, int>((n) => n.index);
    final revision = context.select<Tracker, int>((t) => t.revision);
    final stamp = '$navIndex-$revision';
    if (stamp == _stamp) return;
    _stamp = stamp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
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
    _maybeReload();
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
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.read<AppNav>().goTo(AppNav.tabHistory),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('累计足迹', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text('查看历史记录',
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                  Icon(Icons.chevron_right,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                ]),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
          child: ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('数据备份与恢复', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('导出 / 导入 GPX、CSV 文件', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataBackupPage())),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3))),
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于我们', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('版本信息与隐私说明', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutPage())),
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
