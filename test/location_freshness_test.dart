import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/geo.dart';

void main() {
  group('定位新鲜度校验', () {
    final now = 1700000000000; // 固定“现在”，避免测试抖动

    test('刚刚产生的定位是新鲜的', () {
      expect(isPositionFresh(now - 1000, maxAgeMs: 15000, nowMs: now), isTrue);
    });

    test('系统缓存的旧定位（5 分钟前）被判定为不新鲜', () {
      expect(isPositionFresh(now - 5 * 60 * 1000, maxAgeMs: 15000, nowMs: now),
          isFalse);
    });

    test('恰好在容忍边界上算新鲜', () {
      expect(isPositionFresh(now - 15000, maxAgeMs: 15000, nowMs: now), isTrue);
      expect(isPositionFresh(now - 15001, maxAgeMs: 15000, nowMs: now), isFalse);
    });

    test('未来时间戳（设备时间漂移）不算过期', () {
      expect(isPositionFresh(now + 5000, maxAgeMs: 15000, nowMs: now), isTrue);
    });

    test('不同容忍时长下的表现', () {
      final ts = now - 30 * 1000;
      expect(isPositionFresh(ts, maxAgeMs: 15000, nowMs: now), isFalse);
      expect(isPositionFresh(ts, maxAgeMs: 60000, nowMs: now), isTrue);
    });
  });
}
