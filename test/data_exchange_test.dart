import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/data_exchange.dart';
import 'package:local_footprints/core/models.dart';

TrackExport _sample() {
  final pts = <TrackPoint>[
    TrackPoint(
        sessionId: 0,
        lat: 39.90923,
        lng: 116.397428,
        ts: 1700000000000,
        speed: 0,
        altitude: 44.5),
    TrackPoint(
        sessionId: 0,
        lat: 39.91023,
        lng: 116.398428,
        ts: 1700000060000,
        speed: 1.8,
        altitude: 45.2),
    TrackPoint(
        sessionId: 0,
        lat: 39.91123,
        lng: 116.399428,
        ts: 1700000120000,
        speed: 2.1,
        altitude: 46.0),
  ];
  return TrackExport(type: 'walk', startedAt: pts.first.ts, endedAt: pts.last.ts, points: pts);
}

void main() {
  group('GPX 导出导入', () {
    test('往返保留坐标、高度、时间、类型', () {
      final src = _sample();
      final gpx = exportGpx([src]);
      expect(gpx, contains('<gpx version="1.1"'));
      expect(gpx, contains('<trkpt lat="39.90923" lon="116.397428">'));

      final parsed = parseGpx(gpx);
      expect(parsed.length, 1);
      expect(parsed.first.type, 'walk');
      expect(parsed.first.points.length, 3);
      expect(parsed.first.points.first.lat, closeTo(39.90923, 1e-6));
      expect(parsed.first.points.first.lng, closeTo(116.397428, 1e-6));
      expect(parsed.first.points.first.altitude, closeTo(44.5, 1e-6));
      expect(parsed.first.points.first.ts, 1700000000000);
      expect(parsed.first.points.last.speed, closeTo(2.1, 1e-6));
    });

    test('历史 run 类型导入时归一化为 walk', () {
      final gpx = exportGpx([_sample()]).replaceAll('<type>walk</type>', '<type>run</type>');
      expect(parseGpx(gpx).first.type, 'walk');
    });

    test('多轨迹导出后正确还原为多条', () {
      final a = _sample();
      final b = TrackExport(
          type: 'bike',
          startedAt: 1700100000000,
          points: [
            TrackPoint(
                sessionId: 0,
                lat: 31.23,
                lng: 121.47,
                ts: 1700100000000,
                speed: 5,
                altitude: 10)
          ]);
      final parsed = parseGpx(exportGpx([a, b]));
      expect(parsed.length, 2);
      expect(parsed[1].type, 'bike');
    });
  });

  group('CSV 导出导入', () {
    test('往返保留全部字段', () {
      final src = _sample();
      final csv = exportCsv([src]);
      expect(csv.split('\n').first, csvHeader);

      final parsed = parseCsv(csv);
      expect(parsed.length, 1);
      expect(parsed.first.points.length, 3);
      expect(parsed.first.points.first.lat, closeTo(39.90923, 1e-6));
      expect(parsed.first.points.last.speed, closeTo(2.1, 1e-6));
      expect(parsed.first.points.last.altitude, closeTo(46.0, 1e-6));
    });

    test('缺少 lat/lng 列时抛格式异常', () {
      expect(() => parseCsv('foo,bar\n1,2'), throwsFormatException);
    });
  });

  group('导入统计重算', () {
    test('距离由坐标重新计算，不依赖文件里的统计字段', () {
      final t = _sample();
      final s = t.toSession();
      expect(s.pointCount, 3);
      expect(s.distance, greaterThan(100)); // 约 2×150m
      expect(s.duration, 120);
      expect(s.maxSpeed, closeTo(2.1, 1e-6));
      expect(s.avgSpeed, closeTo(s.distance / 120, 1e-6));
    });

    test('空轨迹安全处理', () {
      final s = TrackExport(type: 'walk', startedAt: 0, points: []).toSession();
      expect(s.pointCount, 0);
      expect(s.distance, 0);
      expect(s.duration, 0);
    });
  });
}
