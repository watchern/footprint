import 'package:flutter_test/flutter_test.dart';
import 'package:local_footprints/core/models.dart';

void main() {
  group('步行跑步合并为行走', () {
    test('选项不再包含 run，walk 显示为行走', () {
      expect(typeNames.containsKey('run'), isFalse);
      expect(typeNames['walk'], '行走');
      expect(typeNames.length, 3);
    });

    test('历史 run 记录归一化为 walk', () {
      expect(normalizeType('run'), 'walk');
      expect(normalizeType('walk'), 'walk');
      expect(normalizeType('bike'), 'bike');
    });

    test('历史 run 记录显示名与颜色等同行走', () {
      expect(typeNameOf('run'), '行走');
      expect(typeColorOf('run'), typeColorOf('walk'));
    });

    test('未知类型原样返回', () {
      expect(typeNameOf('unknown'), 'unknown');
      expect(typeColorOf('unknown'), 0xFF185FA5);
    });
  });
}
