import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/tracker.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  String _selected = 'walk';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmtDuration(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _fmtDistance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';

  Future<void> _start() async {
    final tracker = context.read<Tracker>();
    final ok = await tracker.start(_selected);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无法开始记录：请检查定位权限是否授予、系统定位服务是否开启')));
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<Tracker>().state == TrackState.recording) {
        setState(() {});
      }
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final tracker = context.read<Tracker>();
    final session = await tracker.stop();
    if (!mounted) return;
    if (session != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存：${typeNames[session.type]} ${_fmtDistance(session.distance)}')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('有效轨迹点不足，本次记录未保存')));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<Tracker>();
    final recording = tracker.state == TrackState.recording;

    return Scaffold(
      appBar: AppBar(title: const Text('运动记录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!recording) ...[
                const Text('选择出行方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: typeNames.entries.map((e) {
                    final sel = _selected == e.key;
                    return ChoiceChip(
                      label: Text(e.value),
                      selected: sel,
                      selectedColor: Color(typeColors[e.key]!).withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _selected = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: const Text('开始记录', style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18)),
                  onPressed: _start,
                ),
                const SizedBox(height: 16),
                const Text(
                  '记录期间请保持 App 在前台运行，屏幕将保持常亮。\n所有轨迹数据仅保存在本机，不上传任何服务器。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ] else ...[
                Text(
                  '正在记录：${typeNames[tracker.type]}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                _StatCard(
                    label: '距离', value: _fmtDistance(tracker.distance), big: true),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                          label: '时长',
                          value: _fmtDuration(tracker.elapsedSeconds))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                          label: '均速',
                          value:
                              '${kmh(tracker.avgSpeed).toStringAsFixed(1)} km/h')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                          label: '最高速度',
                          value:
                              '${kmh(tracker.maxSpeed).toStringAsFixed(1)} km/h')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                          label: '轨迹点', value: '${tracker.points.length}')),
                ]),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: const Icon(Icons.stop, size: 28),
                  label: const Text('停止并保存', style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _stop,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  child: const Text('放弃本次记录'),
                  onPressed: () async {
                    _timer?.cancel();
                    await context.read<Tracker>().discard();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool big;
  const _StatCard({required this.label, required this.value, this.big = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: big ? 24 : 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: big ? 40 : 22,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
