import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../core/date_text.dart';
import '../core/db.dart';
import '../core/map_settings.dart';
import '../core/models.dart';
import '../core/mbtiles.dart';
import '../core/scale.dart';
import 'map_page.dart';

class SessionDetail extends StatefulWidget {
  final Session session;
  const SessionDetail({super.key, required this.session});

  @override
  State<SessionDetail> createState() => _SessionDetailState();
}

class _SessionDetailState extends State<SessionDetail> {
  List<TrackPoint> _points = [];
  bool _loaded = false;
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
    final pts = await AppDb.points(widget.session.id!);
    if (!mounted) return;
    setState(() {
      _points = pts;
      _loaded = true;
    });
  }

  String _fmtDur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final settings = context.watch<MapSettings>();
    final sys = settings.coordSystem;
    final gcj = toDisplay(_points, sys);
    final color = Color(typeColorOf(s.type));
    final start = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
    final startStr = formatDateTime(start);

    final offline = settings.activeOffline;
    final TileLayer baseLayer;
    if (offline != null) {
      _offlineReader ??= MbTilesReader(offline.path);
      baseLayer = TileLayer(
        key: ValueKey('offline-detail-${offline.id}'),
        tileProvider: MbTilesProvider(
          reader: _offlineReader!,
          minZoom: offline.minZoom,
          maxZoom: offline.maxZoom,
        ),
        userAgentPackageName: 'local.local_footprints',
        maxNativeZoom: offline.maxZoom,
      );
    } else {
      baseLayer = settings.effectiveSource.toTileLayer(
        template: settings.effectiveUrlTemplate,
        keyValue: settings.tiandituKey,
      );
    }

    final markers = <Marker>[];
    if (gcj.isNotEmpty) {
      markers.add(Marker(
        point: gcj.first,
        width: 20,
        height: 20,
        child: Container(
            decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2))),
      ));
      markers.add(Marker(
        point: gcj.last,
        width: 20,
        height: 20,
        child: Container(
            decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2))),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: Text('${typeNameOf(s.type)}详情')),
      body: Column(children: [
        Expanded(
          flex: 3,
          child: _loaded && gcj.length >= 2
              ? FlutterMap(
                  options: MapOptions(
                    initialCenter: gcj[gcj.length ~/ 2],
                    initialZoom: 15,
                    maxZoom: offlineZoomLimit(
                      offline?.maxZoom,
                      settings.effectiveSource.maxZoom,
                    ),
                    minZoom: 3,
                    // 栅格瓦片文字随旋转会倒转，禁用旋转手势
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    baseLayer,
                    PolylineLayer(polylines: [
                      Polyline(points: gcj, strokeWidth: 5, color: color),
                    ]),
                    MarkerLayer(markers: markers),
                  ],
                )
              : const Center(child: Text('轨迹点不足，无法绘制路线')),
        ),
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(startStr,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _cell('${(s.distance / 1000).toStringAsFixed(2)} km', '里程')),
                  Expanded(child: _cell(_fmtDur(s.duration), '时长')),
                  Expanded(child: _cell(kmh(s.avgSpeed).toStringAsFixed(1), '均速 km/h')),
                  Expanded(child: _cell(kmh(s.maxSpeed).toStringAsFixed(1), '最高 km/h')),
                ]),
                const SizedBox(height: 12),
                Text('${s.pointCount} 个轨迹点',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _cell(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}
