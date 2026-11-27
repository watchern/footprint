import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/date_text.dart';

void main() {
  group('中文日期格式化', () {
    test('输出年/月/日与星期', () {
      final d = DateTime(2026, 11, 28); // 星期六
      expect(formatChineseDay(d), '2026年11月28日 星期六');
    });

    test('星期映射覆盖一整周', () {
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      // 2026-11-23 是星期一
      for (var i = 0; i < 7; i++) {
        final d = DateTime(2026, 11, 23 + i);
        expect(formatChineseDay(d), contains('星期${names[i]}'));
      }
    });

    test('不依赖 intl locale 数据（不会抛异常）', () {
      // 该函数刻意不调用 DateFormat，因此无需 initializeDateFormatting
      expect(() => formatChineseDay(DateTime(2020, 1, 1)), returnsNormally);
      expect(() => formatClockTime(DateTime(2020, 1, 1)), returnsNormally);
      expect(() => formatDateTime(DateTime(2020, 1, 1)), returnsNormally);
    });

    test('时间补零', () {
      expect(formatClockTime(DateTime(2026, 1, 2, 9, 5)), '09:05');
      expect(formatClockTime(DateTime(2026, 1, 2, 23, 59)), '23:59');
    });

    test('日期时间组合格式', () {
      expect(formatDateTime(DateTime(2026, 11, 28, 14, 30)),
          '2026-11-28 14:30');
    });
  });
}
