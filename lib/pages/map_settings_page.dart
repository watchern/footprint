import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/map_settings.dart';
import '../core/mbtiles.dart';
import '../core/tile_source.dart';

class MapSettingsPage extends StatelessWidget {
  const MapSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<MapSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('底图与离线地图')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('在线底图源'),
          const _Hint('所有底图统一使用 XYZ 瓦片协议（{z}/{x}/{y}），'
              '切换源不会影响已记录的轨迹数据。'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: s.sourceId,
            onChanged: (v) {
              if (v != null) s.setSource(v);
            },
            child: Column(
              children: TileSource.builtin.map((src) {
                final active = s.sourceId == src.id && !s.offlineMode;
                return RadioListTile<String>(
                  value: src.id,
                  title: Row(children: [
                    Text(src.name),
                    if (src.recommended) ...[
                      const SizedBox(width: 6),
                      const Chip(
                          label: Text('推荐', style: TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact),
                    ],
                  ]),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('坐标系：${src.coordSystem.label}',
                          style: const TextStyle(fontSize: 12)),
                      if (src.note != null)
                        Text(src.note!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      Text(src.urlTemplate,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black38)),
                    ],
                  ),
                  secondary: active
                      ? const Icon(Icons.check_circle, color: Color(0xFF0F6E56))
                      : null,
                  dense: true,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const _SectionTitle('自定义镜像地址'),
          const _Hint('OSM 在国内访问通常不稳定。可将任意源的地址替换为'
              '你自己搭建或信任的镜像（支持 {z}/{x}/{y}/{s} 占位符）。'),
          const SizedBox(height: 8),
          _MirrorEditor(settings: s),
          const SizedBox(height: 16),
          if (TileSource.byId(s.sourceId).requiresKey) ...[
            const _SectionTitle('天地图 Key'),
            const _Hint('请到天地图官网注册并申请 Key，填入后本应用将使用你的 Key 请求瓦片。'),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: s.tiandituKey,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '天地图 Key',
                hintText: '请到天地图开放平台申请自己的 Key 并替换此占位符',
              ),
              onChanged: s.setTiandituKey,
            ),
            const SizedBox(height: 16),
          ],
          const Divider(height: 32),
          const _SectionTitle('离线地图包'),
          const _Hint('支持导入 .mbtiles 文件（MBTiles 标准）。'
              '可从地图下载工具或镜像站点获取离线包后导入，断网也能查看底图。'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('导入离线地图包'),
            onPressed: () => _import(context, s),
          ),
          const SizedBox(height: 12),
          if (s.offlinePackages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('尚未导入任何离线包',
                  style: TextStyle(fontSize: 13, color: Colors.black45)),
            )
          else
            ...s.offlinePackages.map((p) => _OfflineTile(
                  pkg: p,
                  active: s.activeOfflineId == p.id,
                  settings: s,
                )),
          const SizedBox(height: 24),
          const _SectionTitle('坐标系说明'),
          const _Hint(
            '轨迹数据在数据库中始终保存 GPS 原始坐标（WGS-84），'
            '仅在地图渲染时按当前底图坐标系换算。\n'
            '· 高德 / 腾讯：GCJ-02（国测局加密坐标）\n'
            '· 天地图 / OSM：WGS-84（与国际坐标一致）\n'
            '· 离线 MBTiles：默认 WGS-84，若为国内偏移数据可手动修改。',
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, MapSettings settings) async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final path = file.path;
      if (path == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无法读取所选文件路径')));
        }
        return;
      }
      final f = File(path);
      if (!f.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件不存在')));
        }
        return;
      }
      final pkg = await OfflineImporter.inspect(f);
      if (!context.mounted) return;
      if (pkg == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('解析失败，请确认是标准 .mbtiles 文件')));
        return;
      }
      await settings.addOfflinePackage(pkg);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('已导入「${pkg.name}」，${pkg.tileCount} 张瓦片，${pkg.sizeLabel}')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }
}

class _MirrorEditor extends StatefulWidget {
  final MapSettings settings;
  const _MirrorEditor({required this.settings});

  @override
  State<_MirrorEditor> createState() => _MirrorEditorState();
}

class _MirrorEditorState extends State<_MirrorEditor> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.settings.customUrlTemplate);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _ctl,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: '自定义 XYZ 模板',
          hintText: '例如 https://tile.openstreetmap.de/{z}/{x}/{y}.png',
          helperText: '留空则使用所选源的默认地址',
        ),
        onSubmitted: s.setCustomUrlTemplate,
      ),
      const SizedBox(height: 8),
      Row(children: [
        FilledButton(
          onPressed: () => s.setCustomUrlTemplate(_ctl.text),
          child: const Text('应用'),
        ),
        const SizedBox(width: 8),
        if (s.usingCustomTemplate)
          TextButton(
            onPressed: () {
              _ctl.clear();
              s.setCustomUrlTemplate('');
            },
            child: const Text('恢复默认'),
          ),
      ]),
    ]);
  }
}

class _OfflineTile extends StatelessWidget {
  final OfflinePackage pkg;
  final bool active;
  final MapSettings settings;
  const _OfflineTile({
    required this.pkg,
    required this.active,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: active ? 1.5 : 1),
      ),
      child: ListTile(
        leading: Icon(active ? Icons.layers : Icons.map_outlined,
            color: active ? Theme.of(context).colorScheme.primary : null),
        title: Text(pkg.name,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(
          '缩放 ${pkg.minZoom}–${pkg.maxZoom} · ${pkg.tileCount} 瓦片 · '
          '${pkg.sizeLabel} · ${pkg.coordSystem.label}\n'
          '导入于 ${pkg.importedAt.toString().substring(0, 16)}',
          style: const TextStyle(fontSize: 11, height: 1.5),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(active ? Icons.check_circle : Icons.circle_outlined),
              tooltip: active ? '停用离线底图' : '设为当前底图',
              onPressed: () => settings.setActiveOffline(active ? null : pkg.id),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除离线包'),
                    content: Text('确认删除「${pkg.name}」？'
                        '仅从本应用移除，不会删除原文件。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) await settings.removeOfflinePackage(pkg.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.black54));
}
