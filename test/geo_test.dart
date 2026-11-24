import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/geo.dart';
import 'package:local_footprints/core/mbtiles.dart';
import 'package:local_footprints/core/tile_source.dart';

void main() {
  group('WGS-84 → GCJ-02 纠偏', () {
    test('北京天安门附近应产生数百米级偏移', () {
      // 天安门 WGS-84 坐标
      final wgs = [39.9087, 116.3975];
      final gcj = wgs84ToGcj02(wgs[0], wgs[1]);
      final offsetM = haversine(wgs[0], wgs[1], gcj[0], gcj[1]);
      expect(offsetM, greaterThan(100));
      expect(offsetM, lessThan(1000));
    });

    test('境外坐标不做转换', () {
      final paris = wgs84ToGcj02(48.8566, 2.3522);
      expect(paris[0], closeTo(48.8566, 1e-9));
      expect(paris[1], closeTo(2.3522, 1e-9));
    });

    test('WGS-84 坐标系恒等变换', () {
      final p = CoordSystem.wgs84.fromWgs84(39.9087, 116.3975);
      expect(p[0], 39.9087);
      expect(p[1], 116.3975);
    });

    test('GCJ-02 坐标系走纠偏路径', () {
      final p = CoordSystem.gcj02.fromWgs84(39.9087, 116.3975);
      final expected = wgs84ToGcj02(39.9087, 116.3975);
      expect(p[0], closeTo(expected[0], 1e-9));
      expect(p[1], closeTo(expected[1], 1e-9));
    });
  });

  group('距离计算', () {
    test('同一坐标距离为 0', () {
      expect(haversine(39.9, 116.4, 39.9, 116.4), closeTo(0, 1e-6));
    });

    test('北京到上海约 1060 公里', () {
      final d = haversine(39.9042, 116.4074, 31.2304, 121.4737);
      expect(d / 1000, closeTo(1067, 25));
    });
  });

  group('MBTiles 行号翻转', () {
    test('TMS 行号与 XYZ 行号互为镜像', () {
      // z=12 时 2^12-1 = 4095
      expect(mbtilesRow(12, 1662), 2433);
      expect(mbtilesRow(12, 1663), 2432);
      expect(mbtilesRow(12, 0), 4095);
      expect(mbtilesRow(12, 4095), 0);
    });

    test('翻转是自反的（连续翻转两次回到原值）', () {
      for (final y in [0, 1, 100, 2047, 4094]) {
        expect(mbtilesRow(12, mbtilesRow(12, y)), y);
      }
    });
  });

  group('底图源', () {
    test('默认源为高德，坐标系 GCJ-02', () {
      expect(TileSource.byId('amap').coordSystem, CoordSystem.gcj02);
      expect(TileSource.byId('amap').recommended, isTrue);
    });

    test('OSM 与天地图使用 WGS-84', () {
      expect(TileSource.byId('osm').coordSystem, CoordSystem.wgs84);
      expect(TileSource.byId('tianditu').coordSystem, CoordSystem.wgs84);
    });

    test('所有源使用统一的 XYZ 占位符协议', () {
      for (final s in TileSource.builtin) {
        expect(s.urlTemplate, contains('{z}'));
        expect(s.urlTemplate, contains('{x}'));
        expect(s.urlTemplate, contains('{y}'));
      }
    });

    test('未知 id 回退到默认源', () {
      expect(TileSource.byId('nonexistent').id, 'amap');
    });
  });
}
