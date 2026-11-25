import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/scale.dart';

void main() {
  group('米/像素换算', () {
    test('赤道 z=0 时每像素约 156543 米', () {
      expect(metersPerPixel(0, 0), closeTo(156543.03392804097, 0.001));
    });

    test('缩放一级，米/像素减半', () {
      final a = metersPerPixel(10, 39.9);
      final b = metersPerPixel(11, 39.9);
      expect(a / b, closeTo(2.0, 1e-9));
    });

    test('高纬度米/像素更小（墨卡托压缩）', () {
      expect(metersPerPixel(14, 60), lessThan(metersPerPixel(14, 20)));
    });
  });

  group('刻度选取', () {
    test('选出的刻度宽度不超过上限', () {
      for (final zoom in [8.0, 12.0, 16.0, 18.0]) {
        for (final lat in [20.0, 39.9, 60.0]) {
          final mpp = metersPerPixel(zoom, lat);
          final metric = pickScaleMetric(mpp, kScaleBarMaxWidth);
          expect(metric / mpp, lessThanOrEqualTo(kScaleBarMaxWidth + 1e-6));
        }
      }
    });

    test('总是选到不超过上限的最大候选值', () {
      final mpp = metersPerPixel(14, 39.9);
      final metric = pickScaleMetric(mpp, kScaleBarMaxWidth);
      final next = scaleMetrics.firstWhere((m) => m > metric);
      expect(next / mpp, greaterThan(kScaleBarMaxWidth));
    });

    test('超出所有候选时返回最小值', () {
      expect(pickScaleMetric(0.0000001, 90), 1);
    });
  });

  group('缩放级别反解（定位到 500 米）', () {
    test('反解后比例尺读数恰好为 500 米', () {
      for (final lat in [0.0, 23.1, 39.9, 45.8, 60.0]) {
        final zoom = zoomForScaleMetric(500, lat, kScaleBarMaxWidth);
        final mpp = metersPerPixel(zoom, lat);
        final metric = pickScaleMetric(mpp, kScaleBarMaxWidth);
        expect(metric, 500,
            reason: '纬度 $lat 时应显示 500 米，实际为 $metric');
      }
    });

    test('反解结果在合理缩放区间内', () {
      final zoom = zoomForScaleMetric(500, 39.9, kScaleBarMaxWidth);
      expect(zoom, greaterThan(8));
      expect(zoom, lessThan(20));
    });

    test('纬度越高，同一目标距离所需缩放级别越低', () {
      // 墨卡托在高纬度拉伸更严重：同一 zoom 下 90px 覆盖的地面更少，
      // 因此要把 500m 铺满 90px 需要更大的米/像素，即更低的缩放级别。
      final low = zoomForScaleMetric(500, 20, kScaleBarMaxWidth);
      final high = zoomForScaleMetric(500, 60, kScaleBarMaxWidth);
      expect(high, lessThan(low));
    });

    test('目标距离越大，缩放级别越低', () {
      final near = zoomForScaleMetric(100, 39.9, kScaleBarMaxWidth);
      final far = zoomForScaleMetric(2000, 39.9, kScaleBarMaxWidth);
      expect(far, lessThan(near));
    });
  });

  group('刻度文本格式化', () {
    test('米与千米切换正确', () {
      expect(formatScaleMetric(50), '50 m');
      expect(formatScaleMetric(500), '500 m');
      expect(formatScaleMetric(1000), '1 km');
      expect(formatScaleMetric(2000), '2 km');
      expect(formatScaleMetric(5000), '5 km');
    });
  });
}
