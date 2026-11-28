import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/data_exchange.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/tracker.dart';

/// 数据导出备份 / 导入页面（GPX 1.1 与 CSV）
class DataBackupPage extends StatefulWidget {
  const DataBackupPage({super.key});

  @override
  State<DataBackupPage> createState() => _DataBackupPageState();
}

class _DataBackupPageState extends State<DataBackupPage> {
  int _sessionCount = 0;
  int _pointCount = 0;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final sessions = await AppDb.sessions();
    int pts = 0;
    for (final s in sessions) {
      pts += (await AppDb.points(s.id!)).length;
    }
    if (!mounted) return;
    setState(() {
      _sessionCount = sessions.length;
      _pointCount = pts;
    });
  }

  Future<List<TrackExport>> _readAll() async {
    final sessions = await AppDb.sessions();
    final out = <TrackExport>[];
    for (final s in sessions) {
      final pts = await AppDb.points(s.id!);
      if (pts.isEmpty) continue;
      out.add(TrackExport(
        type: s.type,
        startedAt: s.startedAt,
        endedAt: s.endedAt,
        points: pts,
      ));
    }
    return out;
  }

  void _say(String msg) {
    if (!mounted) return;
    setState(() => _message = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 导出为 GPX 或 CSV
  Future<void> _export(bool gpx) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final tracks = await _readAll();
      if (tracks.isEmpty) {
        _say('暂无轨迹数据可导出');
        return;
      }
      final ext = gpx ? 'gpx' : 'csv';
      final text = gpx ? exportGpx(tracks) : exportCsv(tracks);
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final uri = await FilePicker.saveFile(
        fileName: 'footprints_$stamp.$ext',
        bytes: utf8.encode(text),
        mimeType: gpx
            ? 'application/gpx+xml'
            : 'text/csv',
        dialogTitle: '保存${gpx ? 'GPX' : 'CSV'}备份文件',
      );
      if (uri != null) {
        _say('已导出 ${tracks.length} 条轨迹');
      }
    } catch (e) {
      _say('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 从 GPX 或 CSV 导入
  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择 GPX 或 CSV 文件',
        allowedExtensions: ['gpx', 'csv'],
      );
      if (picked == null) return;

      final name = picked.name.toLowerCase();
      final isGpx = name.endsWith('.gpx');
      final isCsv = name.endsWith('.csv');
      if (!isGpx && !isCsv) {
        _say('仅支持 .gpx 与 .csv 文件');
        return;
      }

      String text;
      if (picked.path != null) {
        text = await File(picked.path!).readAsString();
      } else {
        // file_picker 13：PlatformFile 用 readAsBytes() 读取内容
        text = utf8.decode(await picked.readAsBytes());
      }

      final tracks = isGpx ? parseGpx(text) : parseCsv(text);
      if (tracks.isEmpty) {
        _say('文件中没有可导入的轨迹');
        return;
      }

      for (final t in tracks) {
        final pts = t.points
            .map((p) => TrackPoint(
                  sessionId: 0,
                  lat: p.lat,
                  lng: p.lng,
                  ts: p.ts,
                  speed: p.speed,
                  altitude: p.altitude,
                ))
            .toList();
        await AppDb.insertTrack(t.toSession(), pts);
      }
      // 通知其他页面刷新（时间轴 / 统计）
      if (mounted) context.read<Tracker>().markDataChanged();
      await _loadStats();
      _say('已导入 ${tracks.length} 条轨迹');
    } on FormatException catch (e) {
      _say('文件格式错误：${e.message}');
    } catch (e) {
      _say('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与恢复')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          elevation: 0,
          color: color.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('本地数据',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text('$_sessionCount 条轨迹 · $_pointCount 个定位点',
                  style: TextStyle(fontSize: 13, color: color.onSurfaceVariant)),
              const SizedBox(height: 8),
              const Text('导出文件仅保存在你指定的位置，不经过任何服务器。',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('导出备份', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.download_outlined, color: color.primary),
              title: const Text('导出为 GPX'),
              subtitle: const Text('通用轨迹格式，可在地图软件中打开'),
              trailing: _busy ? null : const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _export(true),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.table_chart_outlined, color: color.primary),
              title: const Text('导出为 CSV'),
              subtitle: const Text('表格格式，便于分析与存档'),
              onTap: _busy ? null : () => _export(false),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('导入恢复', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: Icon(Icons.upload_outlined, color: color.primary),
            title: const Text('从 GPX / CSV 导入'),
            subtitle: const Text('导入的轨迹会追加到现有数据中'),
            onTap: _busy ? null : _import,
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!, style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
