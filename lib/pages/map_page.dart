import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/db.dart';
import '../core/map_settings.dart';
import '../core/mbtiles.dart';
import '../core/models.dart';
import '../core/tile_source.dart';
import '../core/tracker.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<Tracker>();
    final settings = context.watch<MapSettings>();
    final sys = settings.coordSystem;

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

    LatLng? center;
    if (polylines.isNotEmpty) {
      center = polylines.last.points.last;
    } else if (tracker.currentGcj != null) {
      center = LatLng(tracker.currentGcj![0], tracker.currentGcj![1]);
    }

    final markers = <Marker>[];
    if (tracker.currentGcj != null) {
      markers.add(Marker(
        point: LatLng(tracker.currentGcj![0], tracker.currentGcj![1]),
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
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
            initialCenter: center ?? const LatLng(39.909, 116.397),
            initialZoom: center == null ? 4 : 14,
          ),
          children: [
            baseLayer,
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            color: Colors.black.withValues(alpha: 0.35),
            child: Text(
              offline != null
                  ? '离线包：${offline.name} · ${offline.sizeLabel}'
                  : '${settings.effectiveSource.attribution}'
                      '${settings.usingCustomTemplate ? ' · 自定义镜像' : ''}',
              style: const TextStyle(fontSize: 10, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ]),
    );
  }
}
