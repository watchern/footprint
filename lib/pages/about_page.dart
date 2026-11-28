import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 关于我们：版本信息 + 隐私说明（从「我的」页迁入）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    String text;
    try {
      final info = await PackageInfo.fromPlatform();
      text = 'v${info.version} (${info.buildNumber})';
    } catch (_) {
      text = '未知版本';
    }
    if (mounted) setState(() => _version = text);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于我们')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 应用信息卡
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Icon(Icons.map_outlined, size: 48, color: color.primary),
              const SizedBox(height: 12),
              const Text('本地足迹',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('当前版本 $_version',
                  style: TextStyle(fontSize: 13, color: color.onSurfaceVariant)),
              const SizedBox(height: 4),
              const Text('完全本地化的足迹记录应用',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        // 隐私说明卡（从「我的」页迁移）
        Card(
          elevation: 0,
          color: color.surfaceContainerLowest,
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
}
