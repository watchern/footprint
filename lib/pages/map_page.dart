import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/geo.dart';
import '../core/tracker.dart';

/// 高德合规在线底图（GCJ-02），无需 API Key
final TileLayer amapTiles = TileLayer(
  urlTemplate:
      'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
  subdomains: const ['1', '2', '3', '4'],
  userAgentPackageName: 'local.local_footprints',
);

List<LatLng> toGcj(List<TrackPoint> pts) => pts
    .map((p) => wgs84ToGcj02(p.lat, p.lng))
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

  @override
  void initState() {
    super.initState();
    _load();
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
    final all = <LatLng>[];
    for (final s in _sessions) {
      all.addAll(toGcj(_points[s.id!] ?? []));
    }
    if (all.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(all);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)));
  }

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<Tracker>();

    final polylines = <Polyline>[];
    for (final s in _sessions) {
      final pts = toGcj(_points[s.id!] ?? []);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的足迹'),
        actions: [
          IconButton(icon: const Icon(Icons.fit_screen), tooltip: '全览所有轨迹', onPressed: _fitAll),
          IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _load),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center ?? const LatLng(39.909, 116.397),
          initialZoom: center == null ? 4 : 14,
        ),
        children: [
          amapTiles,
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}
