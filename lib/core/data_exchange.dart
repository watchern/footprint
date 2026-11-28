/// 轨迹数据导出 / 导入（GPX 1.1 与 CSV）。
///
/// 设计要点：
/// 1. 编解码都是纯函数，便于单元测试，不依赖平台通道。
/// 2. 坐标一律使用 WGS-84 原始值（数据库口径），不做坐标系转换。
/// 3. 导入时按点重新计算距离/时长/速度，保证统计与轨迹一致。
/// 4. GPX 一个 `trk` 元素对应一次记录；CSV 为扁平表，便于表格软件打开。
library;

import 'dart:convert';

import 'package:xml/xml.dart';

import 'geo.dart';
import 'models.dart';

/// 一条完整轨迹（会话 + 点序列），导出/导入的中间结构
class TrackExport {
  final String type;
  final int startedAt;
  final int? endedAt;
  final List<TrackPoint> points;

  TrackExport({
    required this.type,
    required this.startedAt,
    this.endedAt,
    required this.points,
  });

  /// 由点序列重新计算统计，构造可用于入库的 Session
  Session toSession() {
    if (points.isEmpty) {
      return Session(
        type: type,
        startedAt: startedAt,
        endedAt: endedAt,
        distance: 0,
        duration: 0,
        maxSpeed: 0,
        avgSpeed: 0,
        pointCount: 0,
      );
    }
    double distance = 0;
    double maxSpeed = 0;
    for (int i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      distance += haversine(a.lat, a.lng, b.lat, b.lng);
      if (b.speed > maxSpeed) maxSpeed = b.speed;
    }
    final durationMs = (endedAt ?? points.last.ts) - startedAt;
    final duration = durationMs > 0 ? durationMs ~/ 1000 : 0;
    return Session(
      type: type,
      startedAt: startedAt,
      endedAt: endedAt,
      distance: distance,
      duration: duration,
      maxSpeed: maxSpeed,
      avgSpeed: duration > 0 ? distance / duration : 0,
      pointCount: points.length,
    );
  }
}

// ---------------------------------------------------------------------------
// GPX 1.1
// ---------------------------------------------------------------------------

/// 把若干轨迹导出为 GPX 1.1 文本
String exportGpx(List<TrackExport> tracks) {
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<gpx version="1.1" creator="Local Footprints" '
      'xmlns="http://www.topografix.com/GPX/1/1">');
  for (final t in tracks) {
    b.writeln('  <trk>');
    b.writeln('    <name>${_escapeXml(typeNameOf(t.type))}</name>');
    b.writeln('    <type>${_escapeXml(t.type)}</type>');
    b.writeln('    <trkseg>');
    for (final p in t.points) {
      b.writeln('      <trkpt lat="${p.lat}" lon="${p.lng}">');
      b.writeln('        <ele>${p.altitude}</ele>');
      b.writeln('        <time>${_isoTime(p.ts)}</time>');
      b.writeln('        <speed>${p.speed}</speed>');
      b.writeln('      </trkpt>');
    }
    b.writeln('    </trkseg>');
    b.writeln('  </trk>');
  }
  b.writeln('</gpx>');
  return b.toString();
}

/// 解析 GPX 文本，返回轨迹列表
List<TrackExport> parseGpx(String text) {
  final doc = XmlDocument.parse(text);
  final tracks = <TrackExport>[];
  for (final trk in doc.findAllElements('trk')) {
    final type = trk.findElements('type').firstOrNull?.innerText.trim() ?? 'walk';
    final points = <TrackPoint>[];
    for (final pt in trk.findAllElements('trkpt')) {
      final lat = double.tryParse(pt.getAttribute('lat') ?? '');
      final lng = double.tryParse(pt.getAttribute('lon') ?? '');
      if (lat == null || lng == null) continue;
      final ele = double.tryParse(pt.findElements('ele').firstOrNull?.innerText ?? '') ?? 0;
      final speed = double.tryParse(pt.findElements('speed').firstOrNull?.innerText ?? '') ?? 0;
      final timeText = pt.findElements('time').firstOrNull?.innerText.trim();
      final ts = timeText == null ? 0 : (DateTime.tryParse(timeText)?.millisecondsSinceEpoch ?? 0);
      points.add(TrackPoint(
        sessionId: 0,
        lat: lat,
        lng: lng,
        ts: ts,
        speed: speed,
        altitude: ele,
      ));
    }
    if (points.isEmpty) continue;
    points.sort((a, b) => a.ts.compareTo(b.ts));
    final trkTime = trk.findElements('time').firstOrNull?.innerText.trim();
    final startedAt = (trkTime == null ? null : DateTime.tryParse(trkTime)?.millisecondsSinceEpoch) ??
        points.first.ts;
    tracks.add(TrackExport(
      type: normalizeType(type),
      startedAt: startedAt,
      endedAt: points.length > 1 ? points.last.ts : null,
      points: points,
    ));
  }
  return tracks;
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

const String csvHeader =
    'session_index,type,started_at,lat,lng,timestamp_ms,speed_mps,altitude_m';

/// 把若干轨迹导出为 CSV 文本（每个点一行，会话元数据重复）
String exportCsv(List<TrackExport> tracks) {
  final b = StringBuffer()..writeln(csvHeader);
  for (int i = 0; i < tracks.length; i++) {
    final t = tracks[i];
    for (final p in t.points) {
      b.writeln([
        i,
        t.type,
        t.startedAt,
        _fmt(p.lat),
        _fmt(p.lng),
        p.ts,
        _fmt(p.speed),
        _fmt(p.altitude),
      ].join(','));
    }
  }
  return b.toString();
}

/// 解析 CSV 文本，按 session_index 分组还原轨迹
List<TrackExport> parseCsv(String text) {
  final lines = const LineSplitter().convert(text.trim());
  if (lines.isEmpty) return [];
  final header = _splitCsvLine(lines.first);
  final idx = <String, int>{};
  for (int i = 0; i < header.length; i++) {
    idx[header[i].trim()] = i;
  }
  if (!idx.containsKey('lat') || !idx.containsKey('lng')) {
    throw FormatException('CSV 缺少 lat/lng 列');
  }

  final groups = <int, List<TrackPoint>>{};
  final meta = <int, _CsvMeta>{};
  for (int lineNo = 1; lineNo < lines.length; lineNo++) {
    final line = lines[lineNo].trim();
    if (line.isEmpty) continue;
    final cols = _splitCsvLine(line);
    String? get(String key) {
      final i = idx[key];
      return (i != null && i < cols.length) ? cols[i].trim() : null;
    }

    final lat = double.tryParse(get('lat') ?? '');
    final lng = double.tryParse(get('lng') ?? '');
    if (lat == null || lng == null) continue;
    final group = int.tryParse(get('session_index') ?? '') ?? 0;
    final ts = int.tryParse(get('timestamp_ms') ?? '') ??
        int.tryParse(get('timestamp') ?? '') ??
        0;
    final pt = TrackPoint(
      sessionId: 0,
      lat: lat,
      lng: lng,
      ts: ts,
      speed: double.tryParse(get('speed_mps') ?? '') ?? 0,
      altitude: double.tryParse(get('altitude_m') ?? '') ?? 0,
    );
    groups.putIfAbsent(group, () => []).add(pt);
    meta.putIfAbsent(
        group,
        () => _CsvMeta(
              type: normalizeType(get('type') ?? 'walk'),
              startedAt: int.tryParse(get('started_at') ?? '') ?? ts,
            ));
  }

  final tracks = <TrackExport>[];
  for (final entry in groups.entries) {
    final pts = entry.value..sort((a, b) => a.ts.compareTo(b.ts));
    final m = meta[entry.key]!;
    tracks.add(TrackExport(
      type: m.type,
      startedAt: m.startedAt == 0 ? pts.first.ts : m.startedAt,
      endedAt: pts.length > 1 ? pts.last.ts : null,
      points: pts,
    ));
  }
  return tracks;
}

class _CsvMeta {
  final String type;
  final int startedAt;
  _CsvMeta({required this.type, required this.startedAt});
}

/// 简易 CSV 行拆分（兼容带引号字段）
List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  bool quoted = false;
  for (int i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

String _fmt(double v) => v.toStringAsFixed(6);

String _isoTime(int ms) =>
    ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String() : '';

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
