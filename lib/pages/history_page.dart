import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_nav.dart';
import '../core/date_text.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/tracker.dart';
import 'session_detail.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Session>? _sessions;

  /// 上次触发刷新的数据标记（标签页 + 记录版本号）
  String? _stamp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 数据可能已变化时重新加载。
  ///
  /// 本页位于 IndexedStack 中会常驻不销毁，initState 只执行一次，
  /// 因此必须监听「切回本页」与「保存了新记录」两个信号。
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
    final s = await AppDb.sessions();
    if (!mounted) return;
    setState(() => _sessions = s);
  }

  String _fmtDur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
  }

  @override
  Widget build(BuildContext context) {
    _maybeReload();
    final sessions = _sessions;
    return Scaffold(
      appBar: AppBar(title: const Text('时间轴')),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? const Center(child: Text('还没有记录，去「记录」页开始第一次出行吧'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final s = sessions[i];
                      final day = formatChineseDay(
                          DateTime.fromMillisecondsSinceEpoch(s.startedAt));
                      final showDay = i == 0 ||
                          !_sameDay(sessions[i - 1].startedAt, s.startedAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDay)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(day,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500)),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                      color: Theme.of(context)
                                          .dividerColor
                                          .withValues(alpha: 0.3))),
                              child: ListTile(
                                leading: Container(
                                  width: 10,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Color(typeColorOf(s.type)),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                title: Row(children: [
                                  Text(typeNameOf(s.type),
                                      style: const TextStyle(fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  Text(
                                      _fmtDist(s.distance),
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w500)),
                                ]),
                                subtitle: Text(
                                  '${formatClockTime(DateTime.fromMillisecondsSinceEpoch(s.startedAt))}'
                                  '${s.endedAt != null ? ' – ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(s.endedAt!))}' : ''}'
                                  ' · ${_fmtDur(s.duration)} · 均速 ${kmh(s.avgSpeed).toStringAsFixed(1)} km/h',
                                ),
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => SessionDetail(session: s)));
                                  _load();
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  bool _sameDay(int a, int b) =>
      DateTime.fromMillisecondsSinceEpoch(a).day ==
          DateTime.fromMillisecondsSinceEpoch(b).day &&
      DateTime.fromMillisecondsSinceEpoch(a).month ==
          DateTime.fromMillisecondsSinceEpoch(b).month &&
      DateTime.fromMillisecondsSinceEpoch(a).year ==
          DateTime.fromMillisecondsSinceEpoch(b).year;

  String _fmtDist(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.toStringAsFixed(0)} m';
}
