import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/app_nav.dart';
import '../core/db.dart';
import '../core/location_provider.dart';
import '../core/map_settings.dart';
import '../core/mbtiles.dart';
import '../core/models.dart';
import '../core/scale.dart';
import '../core/tile_source.dart';
import '../core/tracker.dart';
import '../widgets/map_overlays.dart';
import 'map_settings_page.dart';

/// 依据坐标系统一转换：数据库存 WGS-84，渲染时按底图坐标系换算
List<LatLng> toDisplay(List<TrackPoint> pts, CoordSystem sys) => pts
    .map((p) => sys.fromWgs84(p.lat, p.lng))
    .map((c) => LatLng(c[0], c[1]))
    .toList();

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  List<Session> _sessions = [];
  Map<int, List<TrackPoint>> _points = {};
  final MapController _mapController = MapController();
  MbTilesReader? _offlineReader;

  /// 定位按钮是否正在获取位置
  bool _locating = false;

  /// 记录类型（开始按钮直接使用）
  String _recordType = 'walk';

  /// 计时器：刷新记录中的时长
  Timer? _timer;

  /// 上次触发刷新的数据标记（标签页 + 记录版本号）
  String? _stamp;

  @override
  void initState() {
    super.initState();
    _load();
    // 启动后自动定位到当前位置：仅当权限已授予时静默执行（不主动弹窗）。
    // 首次安装未授权时不强弹，待用户点「定位」/「开始记录」授权后，后续启动即可自动定位。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoLocateOnStart();
    });
  }

  /// 启动自动定位：保持默认 2km 比例尺，只把地图中心移到当前位置
  Future<void> _autoLocateOnStart() async {
    final loc = context.read<LocationProvider>();
    // 已授权才启动定位流；未授权不弹窗（尊重按需授权约定）
    final started = await loc.start();
    if (!started || !mounted) return;
    await _moveToCurrent(
      targetScaleMeters: 2000,
      requestPermission: false,
      silent: true,
    );
  }

  /// 切回本页或新增记录时刷新轨迹数据
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

  @override
  void dispose() {
    _timer?.cancel();
    _offlineReader?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await AppDb.sessions();
    final map = <int, List<TrackPoint>>{};
    for (final s in sessions) {
      map[s.id!] = await AppDb.points(s.id!);
    }
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _points = map;
    });
  }

  void _fitAll() {
    final sys = context.read<MapSettings>().coordSystem;
    final all = <LatLng>[];
    for (final s in _sessions) {
      all.addAll(toDisplay(_points[s.id!] ?? [], sys));
    }
    if (all.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(all);
    _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)));
  }

  /// 定位到当前位置，并把比例尺缩放到 500 米
  Future<void> _locateMe() async {
    await _moveToCurrent(
      targetScaleMeters: 500,
      requestPermission: true,
      silent: false,
    );
  }

  /// 把地图移到当前位置，比例尺缩放到 [targetScaleMeters] 对应的读数。
  ///
  /// [requestPermission] 为 true 时会按需申请权限（用户主动点击定位）；
  /// [silent] 为 true 时不显示 loading 与失败提示（启动自动定位用）。
  Future<void> _moveToCurrent({
    required double targetScaleMeters,
    required bool requestPermission,
    required bool silent,
  }) async {
    if (!silent) setState(() => _locating = true);
    final loc = context.read<LocationProvider>();
    // 先确保定位流在跑，等待新点时才有数据可等
    await loc.start(requestIfNeeded: requestPermission);
    // 取可靠坐标：拒绝系统缓存的「最后已知位置」
    final p = await loc.acquireReliable();
    if (!mounted) return;
    if (!silent) setState(() => _locating = false);

    if (p == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('定位失败：未能获取到新的定位，请到室外或开启系统定位服务后重试')));
      }
      return;
    }

    final sys = context.read<MapSettings>().coordSystem;
    final disp = sys.fromWgs84(p.latitude, p.longitude);
    final target = LatLng(disp[0], disp[1]);
    final zoom = zoomForScaleMetric(targetScaleMeters, disp[0], kScaleBarMaxWidth);
    _mapController.move(target, zoom);

    // 精度过差时给出可操作的提示（Android 12+ 可能是「大致位置」授权）
    final acc = p.accuracy;
    if (!silent && acc > 30) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('当前定位精度约 ${acc.round()} 米，'
              '如偏差较大请检查系统设置中是否已授予「精确位置」权限')));
    }
  }

  /// 开始 / 停止记录
  Future<void> _toggleRecord() async {
    final tracker = context.read<Tracker>();
    if (tracker.state == TrackState.recording) {
      _timer?.cancel();
      final session = await tracker.stop();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(session != null
                ? '已保存：${typeNames[session.type]} '
                    '${(session.distance / 1000).toStringAsFixed(2)} km'
                : '有效轨迹点不足，本次记录未保存')),
      );
      return;
    }

    // 开始：确保位置流已启动并订阅（此处按需请求定位权限）
    final loc = context.read<LocationProvider>();
    final ok = await loc.start(requestIfNeeded: true);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无法开始记录：请检查定位权限是否授予、系统定位服务是否开启')));
      return;
    }
    await tracker.start(_recordType);
    tracker.attachLocationStream(loc.positionStream);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && tracker.state == TrackState.recording) {
        setState(() {});
      }
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _maybeReload();
    final tracker = context.watch<Tracker>();
    final settings = context.watch<MapSettings>();
    final location = context.watch<LocationProvider>();
    final sys = settings.coordSystem;
    final recording = tracker.state == TrackState.recording;

    final polylines = <Polyline>[];
    for (final s in _sessions) {
      final pts = toDisplay(_points[s.id!] ?? [], sys);
      if (pts.length < 2) continue;
      polylines.add(Polyline(
        points: pts,
        strokeWidth: 4,
        color: Color(typeColors[s.type] ?? 0xFF185FA5),
      ));
    }

    // 当前位置（渲染层按底图坐标系换算）
    final curRaw = location.position != null
        ? [location.position!.latitude, location.position!.longitude]
        : tracker.currentWgs;
    final curDisp = curRaw == null ? null : sys.fromWgs84(curRaw[0], curRaw[1]);
    final curPoint = curDisp == null ? null : LatLng(curDisp[0], curDisp[1]);

    LatLng? center;
    if (polylines.isNotEmpty) {
      center = polylines.last.points.last;
    } else if (curPoint != null) {
      center = curPoint;
    }
    center ??= const LatLng(39.909, 116.397);

    // 初始缩放：使比例尺读数为 2 公里
    final initialZoom =
        zoomForScaleMetric(2000, center.latitude, kScaleBarMaxWidth);

    final markers = <Marker>[];
    final circles = <CircleMarker>[];
    if (curPoint != null) {
      // 精度圈
      final acc = location.accuracy;
      if (acc != null && acc > 0) {
        circles.add(CircleMarker(
          point: curPoint,
          radius: acc,
          useRadiusInMeter: true,
          color: const Color(0xFF1A73E8).withValues(alpha: 0.13),
          borderColor: const Color(0xFF1A73E8).withValues(alpha: 0.32),
          borderStrokeWidth: 1,
        ));
      }
      // 方向箭头标
      markers.add(Marker(
        point: curPoint,
        width: 88,
        height: 88,
        alignment: Alignment.center,
        child: HeadingIndicator(
          heading: location.heading,
          accuracy: acc,
        ),
      ));
    }

    // 底图：离线包优先，否则在线源
    final offline = settings.activeOffline;
    final TileLayer baseLayer;
    if (offline != null) {
      _offlineReader ??= MbTilesReader(offline.path);
      baseLayer = TileLayer(
        key: ValueKey('offline-${offline.id}'),
        tileProvider: MbTilesProvider(
          reader: _offlineReader!,
          minZoom: offline.minZoom,
          maxZoom: offline.maxZoom,
        ),
        userAgentPackageName: 'local.local_footprints',
        maxNativeZoom: 19,
      );
    } else {
      baseLayer = settings.effectiveSource.toTileLayer(
        template: settings.effectiveUrlTemplate,
        keyValue: settings.tiandituKey,
      );
    }

    final attribution = offline != null
        ? '离线包：${offline.name}'
        : '${settings.effectiveSource.attribution}'
            '${settings.usingCustomTemplate ? ' · 自定义镜像' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的足迹'),
        actions: [
          IconButton(
              icon: const Icon(Icons.fit_screen),
              tooltip: '全览所有轨迹',
              onPressed: _fitAll),
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: '底图与离线地图',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MapSettingsPage()));
              if (mounted) _load();
            },
          ),
          IconButton(
              icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _load),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: initialZoom,
          ),
          children: [
            baseLayer,
            CircleLayer(circles: circles),
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
            // 左下角比例尺
            ScaleBar(
              maxWidth: kScaleBarMaxWidth,
              attribution: attribution,
            ),
          ],
        ),

        // 右下角：定位到当前位置
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'locate',
            onPressed: _locating ? null : _locateMe,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
            tooltip: '定位到当前位置（比例尺 500 米）',
            child: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
          ),
        ),

        // 底部中间：开始 / 停止记录
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: Center(
            child: _RecordBar(
              recording: recording,
              type: _recordType,
              elapsed: tracker.elapsedSeconds,
              distance: tracker.distance,
              onTypeChanged: (t) => setState(() => _recordType = t),
              onToggle: _toggleRecord,
            ),
          ),
        ),
      ]),
    );
  }
}

/// 底部记录控制条：未记录时选择出行方式，记录中显示实时数据
class _RecordBar extends StatelessWidget {
  final bool recording;
  final String type;
  final int elapsed;
  final double distance;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onToggle;

  const _RecordBar({
    required this.recording,
    required this.type,
    required this.elapsed,
    required this.distance,
    required this.onTypeChanged,
    required this.onToggle,
  });

  String _fmtDur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: recording
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_fmtDur(elapsed),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                  Text('${(distance / 1000).toStringAsFixed(2)} km',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: primary)),
                ]),
              ),
              const SizedBox(width: 4),
              // 用普通 FilledButton + 单一子组件，保证图标在圆内居中
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                  minimumSize: const Size(46, 46),
                ),
                onPressed: onToggle,
                child: const Icon(Icons.stop, size: 22),
              ),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in typeNames.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text(e.value, style: const TextStyle(fontSize: 13)),
                    selected: type == e.key,
                    selectedColor: Color(typeColors[e.key]!).withValues(alpha: 0.22),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onTypeChanged(e.key),
                  ),
                ),
              const SizedBox(width: 4),
              FloatingActionButton.small(
                heroTag: 'startRecord',
                onPressed: onToggle,
                backgroundColor: primary,
                foregroundColor: Colors.white,
                tooltip: '开始记录',
                child: const Icon(Icons.play_arrow),
              ),
            ]),
    );
  }
}
